{ lib, nixlite }:
let
  inherit (nixlite) merge mergeAll;
  nixliteImport = nixlite.import;

  # Deep-force the value so tryEval catches throws buried in lazy attrs/list
  # elements (e.g. `merge { a.b.c = 1; } { a.b.c = 2; }` only throws when
  # `.a.b.c` is demanded).
  throws = e: !(builtins.tryEval (builtins.deepSeq e null)).success;

  fix = ./fixtures;
  flat = ./fixtures-flat;

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
    # (default.nix is now treated as a normal file: no collapse, no root exclusion)
    import_pathFormKeys = {
      expr = builtins.attrNames noResolve;
      expected = [ "default" "dir-recurse" "dir-with-def" "fn" "plain" "root-default-sibling" ];
    };
    import_rootDefaultPresent = {
      expr = noResolve.default;
      expected = { rootDefault = "must not appear as a key"; };
    };
    import_plainPassthrough = {
      expr = noResolve.plain;
      expected = { plain = true; };
    };
    import_fnStaysFunction = {
      expr = builtins.isFunction noResolve.fn;
      expected = true;
    };
    import_dirWithDefNowRecurses = {
      # dir-with-def no longer collapses; it's walked like any other directory
      # and its default.nix appears as a `default` key.
      expr = builtins.attrNames noResolve."dir-with-def";
      expected = [ "default" "ignored" ];
    };
    import_dirWithDefDefaultStaysFunction = {
      expr = builtins.isFunction noResolve."dir-with-def".default;
      expected = true;
    };
    import_dirWithDefSiblingPresent = {
      expr = noResolve."dir-with-def".ignored;
      expected = { must = "be ignored when sibling default.nix exists"; };
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
    import_rootDefaultSiblingNotCollapsed = {
      # root-default-sibling/default.nix no longer collapses the parent dir.
      expr = noResolve.root-default-sibling;
      expected = { default = { collapsed = true; }; };
    };

    # import — attrset form with resolve
    importR_fnApplied = {
      expr = withResolve.fn;
      expected = { gotArgs = { tag = "R"; }; };
    };
    importR_dirWithDefApplied = {
      expr = withResolve."dir-with-def".default;
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

    # import — flatten
    import_flattenSinglePath = {
      expr = nixliteImport { path = flat; flatten = true; };
      expected = [ { a = 1; } { b = 2; } { c = 3; } ];
    };
    import_flattenListOfFiles = {
      expr = nixliteImport {
        path = [ (flat + "/a.nix") (flat + "/b.nix") ];
        flatten = true;
      };
      expected = [ { a = 1; } { b = 2; } ];
    };
    import_flattenListOfDirs = {
      expr = nixliteImport {
        path = [ (flat + "/sub") flat ];
        flatten = true;
      };
      expected = [ { c = 3; } { a = 1; } { b = 2; } { c = 3; } ];
    };
    import_flattenListMixed = {
      expr = nixliteImport {
        path = [ (flat + "/a.nix") (flat + "/sub") ];
        flatten = true;
      };
      expected = [ { a = 1; } { c = 3; } ];
    };
    import_flattenWithResolve = {
      expr = nixliteImport {
        path = flat;
        flatten = true;
        resolve = { tag = "F"; };
      };
      # No functions in fixtures-flat, so resolve is a no-op; same result.
      expected = [ { a = 1; } { b = 2; } { c = 3; } ];
    };
    import_flattenListWithResolveAppliesToFnLeaf = {
      # dir-with-def/default.nix is a function; flatten + resolve applies it.
      expr = nixliteImport {
        path = [ (fix + "/dir-with-def") ];
        flatten = true;
        resolve = { tag = "F"; };
      };
      expected = [
        { dirFn = { tag = "F"; }; }
        { must = "be ignored when sibling default.nix exists"; }
      ];
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
    import_throwsListPathWithoutFlatten = {
      expr = throws (nixliteImport { path = [ flat ]; });
      expected = true;
    };
    import_throwsFlattenWithBadPathType = {
      # path is neither a path nor list of paths
      expr = throws (nixliteImport { path = "str"; flatten = true; });
      expected = true;
    };
    import_throwsListPathWithNonPathElement = {
      expr = throws (nixliteImport { path = [ flat "str" ]; flatten = true; });
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
