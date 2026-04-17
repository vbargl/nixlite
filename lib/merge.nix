{ lib }:
let
  inherit (builtins) typeOf isAttrs isList isFunction attrNames foldl';

  isPrimitive = t:
    t == "bool" || t == "int" || t == "float" || t == "string" || t == "path";

  pathStr = path: if path == "" then "<root>" else path;

  mergeAt = path: a: b:
    let
      ta = typeOf a;
      tb = typeOf b;
    in
    if ta == "null" then b
    else if tb == "null" then a
    else if isFunction a || isFunction b then
      throw "nixtra.merge: cannot merge function at ${pathStr path} (${ta} vs ${tb})"
    else if isAttrs a && isAttrs b then
      let
        keys = attrNames (a // b);
        valueFor = k:
          let sub = "${path}.${k}"; in
          if (a ? ${k}) && (b ? ${k}) then mergeAt sub a.${k} b.${k}
          else if a ? ${k} then a.${k}
          else b.${k};
      in
      builtins.listToAttrs (map (k: { name = k; value = valueFor k; }) keys)
    else if isList a && isList b then
      a ++ b
    else if isPrimitive ta && isPrimitive tb then
      if ta == tb && a == b then a
      else throw "nixtra.merge: conflict at ${pathStr path} (${toString a} vs ${toString b})"
    else
      throw "nixtra.merge: incompatible types at ${pathStr path} (${ta} vs ${tb})";

  merge = a: b: mergeAt "" a b;

  mergeList = xs: foldl' merge { } xs;
in
{ inherit merge mergeList; }
