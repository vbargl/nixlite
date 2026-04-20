{ lib, nixlite }:
let
  inherit (nixlite) merge mergeAll;
  nixliteImport = nixlite.import;

  # Deep-force the value so tryEval catches throws buried in lazy attrs/list
  # elements (e.g. `merge { a.b.c = 1; } { a.b.c = 2; }` only throws when
  # `.a.b.c` is demanded).
  throws = e: !(builtins.tryEval (builtins.deepSeq e null)).success;

  fix = ./fixtures;

  noResolve = nixliteImport fix;
  args = { tag = "R"; };
  withResolve = nixliteImport { path = fix; resolve = args; };

  evalTests = import ./eval.nix { inherit lib nixlite; };

  tests = evalTests // {
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

    # merge — error messages contain path + values (the throw only fires when
    # the conflicting leaf is demanded, so force-evaluate the whole result).
    merge_errorMessagePath =
      let r = builtins.tryEval (builtins.deepSeq (merge { a.b.c = 1; } { a.b.c = 2; }) null); in
      { expr = r.success; expected = false; };

    # mergeAll
    mergeAll_empty = { expr = mergeAll [ ]; expected = { }; };
    mergeAll_singleton = {
      expr = mergeAll [ { a = 1; } ];
      expected = { a = 1; };
    };
    mergeAll_triple = {
      expr = mergeAll [ { a = 1; } { b = 2; } { c = 3; } ];
      expected = { a = 1; b = 2; c = 3; };
    };
    mergeAll_nestedAndLists = {
      expr = mergeAll [
        { x.a = 1; }
        { x.b = 2; }
        { y = [ 1 ]; }
        { y = [ 2 ]; }
      ];
      expected = { x = { a = 1; b = 2; }; y = [ 1 2 ]; };
    };
    mergeAll_equivalentToFold = {
      expr = mergeAll [ { a = 1; } { b = 2; } { c = 3; } ]
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
      expr = (nixliteImport { path = fix; }).plain;
      expected = noResolve.plain;
    };
    importAttrs_noResolveFnStaysFunction = {
      expr = builtins.isFunction (nixliteImport { path = fix; }).fn;
      expected = true;
    };

    # import — error cases
    import_throwsUnknownKey = {
      expr = throws (nixliteImport { path = fix; bogus = 1; });
      expected = true;
    };
    import_throwsMissingPath = {
      expr = throws (nixliteImport { resolve = { }; });
      expected = true;
    };
    import_throwsBadArg = {
      expr = throws (nixliteImport "string");
      expected = true;
    };
    import_throwsNullArg = {
      expr = throws (nixliteImport null);
      expected = true;
    };
  };

  # lib.runTests only runs keys prefixed with "test"; add the prefix here so
  # we can keep readable names above.
  prefixed = lib.mapAttrs' (name: value: lib.nameValuePair "test_${name}" value) tests;
  failures = lib.runTests prefixed;
in
{
  inherit tests failures;
  pass = failures == [ ];
}
