{ lib, nixtra }:
let
  inherit (nixtra) merge mergeList;
  nixtraImport = nixtra.import;

  try = e: builtins.tryEval e;
  throws = e: !(try e).success;

  fix = ./fixtures;

  noResolve = nixtraImport fix;
  args = { tag = "R"; };
  withResolve = nixtraImport { path = fix; resolve = args; };

  tests = {
    # merge — attrset cases
    merge_disjoint = {
      expr = merge { a = 1; } { b = 2; };
      expected = { a = 1; b = 2; };
    };
    merge_nestedRecurse = {
      expr = merge { x = { a = 1; }; } { x = { b = 2; }; };
      expected = { x = { a = 1; b = 2; }; };
    };
    merge_overlapEqualAttrs = {
      expr = merge { a = 1; b = 2; } { b = 2; c = 3; };
      expected = { a = 1; b = 2; c = 3; };
    };

    # merge — list cases
    merge_listConcat = {
      expr = merge [ 1 2 ] [ 3 4 ];
      expected = [ 1 2 3 4 ];
    };
    merge_listOrder = {
      expr = merge [ "a" ] [ "b" ];
      expected = [ "a" "b" ];
    };

    # merge — primitives
    merge_intEqual = { expr = merge 5 5; expected = 5; };
    merge_stringEqual = { expr = merge "x" "x"; expected = "x"; };
    merge_boolEqual = { expr = merge true true; expected = true; };
    merge_floatEqual = { expr = merge 1.5 1.5; expected = 1.5; };

    # merge — null absorption
    merge_nullLeft = { expr = merge null 7; expected = 7; };
    merge_nullRight = { expr = merge 7 null; expected = 7; };
    merge_nullBoth = { expr = merge null null; expected = null; };
    merge_nullAbsorbAttrs = {
      expr = merge null { a = 1; };
      expected = { a = 1; };
    };

    # merge — throws
    merge_throwsPrimConflict = { expr = throws (merge 1 2); expected = true; };
    merge_throwsListVsAttrs = { expr = throws (merge [ 1 ] { a = 1; }); expected = true; };
    merge_throwsFnLeft = { expr = throws (merge (x: x) { }); expected = true; };
    merge_throwsFnRight = { expr = throws (merge { } (x: x)); expected = true; };
    merge_throwsPrimVsAttrs = { expr = throws (merge 1 { }); expected = true; };

    # merge — error messages contain path + values
    merge_errorMessagePath =
      let r = builtins.tryEval (merge { a.b.c = 1; } { a.b.c = 2; }); in
      { expr = r.success; expected = false; };

    # mergeList
    mergeList_empty = { expr = mergeList [ ]; expected = { }; };
    mergeList_singleton = {
      expr = mergeList [ { a = 1; } ];
      expected = { a = 1; };
    };
    mergeList_triple = {
      expr = mergeList [ { a = 1; } { b = 2; } { c = 3; } ];
      expected = { a = 1; b = 2; c = 3; };
    };
    mergeList_nestedAndLists = {
      expr = mergeList [
        { x.a = 1; }
        { x.b = 2; }
        { y = [ 1 ]; }
        { y = [ 2 ]; }
      ];
      expected = { x = { a = 1; b = 2; }; y = [ 1 2 ]; };
    };
    mergeList_equivalentToFold = {
      expr = mergeList [ { a = 1; } { b = 2; } { c = 3; } ]
        == merge (merge { a = 1; } { b = 2; }) { c = 3; };
      expected = true;
    };

    # import — path form, structure
    import_pathFormKeys = {
      expr = builtins.attrNames noResolve;
      expected = [ "dir-recurse" "dir-with-def" "fn" "plain" "root-default-sibling" ];
    };
    import_rootDefaultExcluded = {
      expr = noResolve ? rootDefault;
      expected = false;
    };
    import_plainPassthrough = {
      expr = noResolve.plain;
      expected = { plain = true; };
    };
    import_fnStaysFunction = {
      expr = builtins.isFunction noResolve.fn;
      expected = true;
    };
    import_dirWithDefStaysFunction = {
      expr = builtins.isFunction noResolve."dir-with-def";
      expected = true;
    };
    import_dirWithDefIgnoresSiblings = {
      # dir-with-def/ignored.nix must NOT appear as a subkey
      expr = (noResolve."dir-with-def" args) ? ignored;
      expected = false;
    };
    import_dirRecurseHasSub = {
      expr = builtins.attrNames noResolve."dir-recurse";
      expected = [ "other" "sub" ];
    };
    import_nestedFnStaysFunction = {
      expr = builtins.isFunction noResolve."dir-recurse".sub.leaf;
      expected = true;
    };
    import_nestedNonFnPassthrough = {
      expr = noResolve."dir-recurse".other;
      expected = { notAFn = 1; };
    };
    import_rootDefaultSiblingCollapsed = {
      expr = noResolve.root-default-sibling;
      expected = { collapsed = true; };
    };

    # import — attrset form with resolve
    importR_fnApplied = {
      expr = withResolve.fn;
      expected = { gotArgs = { tag = "R"; }; };
    };
    importR_dirWithDefApplied = {
      expr = withResolve."dir-with-def";
      expected = { dirFn = { tag = "R"; }; };
    };
    importR_nestedFnApplied = {
      expr = withResolve."dir-recurse".sub.leaf;
      expected = { nestedFn = { tag = "R"; }; };
    };
    importR_nonFnUntouched = {
      expr = withResolve."dir-recurse".other;
      expected = { notAFn = 1; };
    };
    importR_plainUntouched = {
      expr = withResolve.plain;
      expected = { plain = true; };
    };

    # import — attrset form without resolve — same as path form
    importAttrs_noResolveEqualsPathForm = {
      expr = (nixtraImport { path = fix; }).plain;
      expected = noResolve.plain;
    };
    importAttrs_noResolveFnStaysFunction = {
      expr = builtins.isFunction (nixtraImport { path = fix; }).fn;
      expected = true;
    };

    # import — error cases
    import_throwsUnknownKey = {
      expr = throws (nixtraImport { path = fix; bogus = 1; });
      expected = true;
    };
    import_throwsMissingPath = {
      expr = throws (nixtraImport { resolve = { }; });
      expected = true;
    };
    import_throwsBadArg = {
      expr = throws (nixtraImport "string");
      expected = true;
    };
    import_throwsNullArg = {
      expr = throws (nixtraImport null);
      expected = true;
    };
  };

  failures = lib.runTests tests;
in
{
  inherit tests failures;
  pass = failures == [ ];
}
