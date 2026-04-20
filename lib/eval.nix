{ lib }:
let
  inherit (builtins)
    isAttrs
    isList
    isFunction
    isPath
    typeOf
    elem
    removeAttrs
    attrNames
    filter
    head
    tail
    ;
  inherit (import ./merge.nix { inherit lib; }) mergeAll;

  # Like `assert`, but with a custom error message. Prepends the
  # `nixlite.eval:` prefix. Intended for use as
  # `assert require cond "msg"; rest`.
  withMessage = cond: msg: cond || throw "nixlite.eval: ${msg}";

  validKeys = [
    "inputs"
    "module"
  ];

  # Each pending entry carries the context it appeared in: `allowPath = true`
  # means it came from inside a list (or `imports`), where paths are legal.
  # Return values from functions and `import` are `allowPath = false`, so a
  # function returning a bare path or a path file producing another bare path
  # throws instead of being silently re-imported.
  entry = allowPath: value: { inherit allowPath value; };

  wrapList = xs: map (entry true) xs;

  stepInList = "path/attrset/function/list";
  stepReturn = "attrset/function/list";
  allowedMsg = allowPath: if allowPath then stepInList else stepReturn;

  expand =
    args: state: pending:
    if pending == [ ] then
      state
    else
      let
        cur = head pending;
        rest = tail pending;
        v = cur.value;
      in
      if isFunction v then
        expand args state ([ (entry false (v args)) ] ++ rest)
      else if isPath v then
        assert withMessage cur.allowPath "expected ${stepReturn}, got path";
        if elem v state.paths then
          expand args state rest
        else
          expand args (state // { paths = state.paths ++ [ v ]; }) ([ (entry false (import v)) ] ++ rest)
      else if isList v then
        expand args state (wrapList v ++ rest)
      else if isAttrs v then
        let
          hasImports = v ? imports;
          importsVal = v.imports or [ ];
        in
        assert withMessage (
          !hasImports || isList importsVal
        ) "'imports' must be a list, got ${typeOf importsVal}";
        let
          payload = removeAttrs v [ "imports" ];
          newState = state // {
            payloads = state.payloads ++ [ payload ];
          };
        in
        expand args newState (wrapList importsVal ++ rest)
      else
        throw "nixlite.eval: expected ${allowedMsg cur.allowPath}, got ${typeOf v}";

  checkRoot =
    m:
    assert withMessage (
      isAttrs m || isList m || isFunction m
    ) "expected attrset/list/function at root, got ${typeOf m}";
    m;

  nixliteEval =
    arg:
    let
      unknown = filter (k: !(elem k validKeys)) (attrNames arg);
      inputs = arg.inputs or { };
      root = checkRoot arg.module;
    in
    assert withMessage (isAttrs arg) "expected attrset argument, got ${typeOf arg}";
    assert withMessage (unknown == [ ]) "unknown key '${head unknown}' in argument attrset";
    assert withMessage (arg ? module) "missing required key 'module' in argument attrset";
    assert withMessage (!(inputs ? self)) "'self' is reserved and cannot appear in inputs";
    lib.fix (
      self:
      let
        args = inputs // {
          inherit self;
        };
        result = expand args {
          paths = [ ];
          payloads = [ ];
        } [ (entry false root) ];
      in
      mergeAll result.payloads
    );
in
nixliteEval
