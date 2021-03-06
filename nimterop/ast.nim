import strformat, strutils, tables

import regex

import treesitter/runtime

import "."/[getters, globals, grammar]

const gAtoms = @[
  "field_identifier",
  "identifier",
  "shift_expression",
  "math_expression",
  "number_literal",
  "preproc_arg",
  "primitive_type",
  "sized_type_specifier",
  "type_identifier"
]

proc saveNodeData(node: TSNode): bool =
  let name = $node.tsNodeType()
  if name in gAtoms:
    var
      val = node.getNodeVal()

    if name == "primitive_type" and node.tsNodeParent.tsNodeType() == "sized_type_specifier":
      return true

    if name == "number_literal" and $node.tsNodeParent.tsNodeType() in ["shift_expression", "math_expression"]:
      return true

    if name in ["math_expression", "primitive_type", "sized_type_specifier"]:
      val = val.getType()

    let
      pname = node.getPName()
      ppname = node.tsNodeParent().getPName()

    if node.tsNodePrevNamedSibling().tsNodeIsNull():
      if pname == "pointer_declarator":
        if ppname notin ["function_declarator", "array_declarator"]:
          gStateRT.data.add(("pointer_declarator", ""))
        elif ppname == "array_declarator":
          gStateRT.data.add(("array_pointer_declarator", ""))
      elif pname in ["function_declarator", "array_declarator"]:
        if ppname == "pointer_declarator":
          gStateRT.data.add(("pointer_declarator", ""))

    gStateRT.data.add((name, val))

    if node.tsNodeType() == "field_identifier" and
      pname == "pointer_declarator" and
      ppname == "function_declarator":
      gStateRT.data.add(("function_declarator", ""))

  elif name in ["abstract_pointer_declarator", "enumerator", "field_declaration", "function_declarator"]:
    gStateRT.data.add((name.replace("abstract_", ""), ""))

  return true

proc searchAstForNode(ast: ref Ast, node: TSNode): bool =
  let
    childNames = node.getTSNodeNamedChildNames().join()

  if ast.isNil:
    return

  if ast.children.len != 0:
    if childNames.contains(ast.regex):
      if node.getTSNodeNamedChildCountSansComments() != 0:
        var flag = true
        for i in 0 .. node.tsNodeNamedChildCount()-1:
          if $node.tsNodeNamedChild(i).tsNodeType() != "comment":
            let
              nodeChild = node.tsNodeNamedChild(i)
              astChild = ast.getAstChildByName($nodeChild.tsNodeType())
            if not searchAstForNode(astChild, nodeChild):
              flag = false
              break

        if flag:
          return node.saveNodeData()
      else:
        return node.saveNodeData()
  elif node.getTSNodeNamedChildCountSansComments() == 0:
    return node.saveNodeData()

proc searchAst(root: TSNode) =
  var
    node = root
    nextnode: TSNode

  while true:
    if not node.tsNodeIsNull():
      let
        name = $node.tsNodeType()
      if name in gStateRT.ast:
        for ast in gStateRT.ast[name]:
          if searchAstForNode(ast, node):
            ast.tonim(ast, node)
            if gStateRT.debug:
              gStateRT.debugStr &= "\n\n# " & gStateRT.data.join("\n# ")
            break
        gStateRT.data = @[]
    else:
      return

    if $node.tsNodeType() notin gStateRT.ast and node.tsNodeNamedChildCount() != 0:
      nextnode = node.tsNodeNamedChild(0)
    else:
      nextnode = node.tsNodeNextNamedSibling()

    if nextnode.tsNodeIsNull():
      while true:
        node = node.tsNodeParent()
        if node == root:
          break
        if not node.tsNodeNextNamedSibling().tsNodeIsNull():
          node = node.tsNodeNextNamedSibling()
          break
    else:
      node = nextnode

    if node == root:
      break

proc printNim*(fullpath: string, root: TSNode) =
  parseGrammar()

  echo "{.experimental: \"codeReordering\".}"

  var fp = fullpath.replace("\\", "/")
  gStateRT.currentHeader = getCurrentHeader(fullpath)
  gStateRT.constStr &= &"  {gStateRT.currentHeader} = \"{fp}\"\n"

  root.searchAst()

  if gStateRT.enumStr.nBl:
    echo gStateRT.enumStr

  if gStateRT.constStr.nBl:
    echo "const\n" & gStateRT.constStr

  if gStateRT.typeStr.nBl:
    echo "type\n" & gStateRT.typeStr

  if gStateRT.procStr.nBl:
    echo gStateRT.procStr

  if gStateRT.debug and gStateRT.debugStr.nBl:
    echo gStateRT.debugStr