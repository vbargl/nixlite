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
    # Default behavior matches builtins.import: a directory containing
    # default.nix collapses to its import.
    import_pathFormKeys = {
      expr = builtins.attrNames noResolve;
      expected = [ "dir-recurse" "dir-with-def" "fn" "plain" "root-default-sibling" ];
    };
    import_plainPassthrough = {
      expr = noResolve.plain;
      expected = { plain = true; };
    };
    import_fnStaysFunction = {
      expr = builtins.isFunction noResolve.fn;
      expected = true;
    };
    import_dirWithDefCollapsed = {
      # dir-with-def/default.nix is a function; the dir collapses to that
      # function (siblings like ignored.nix are not walked).
      expr = builtins.isFunction noResolve."dir-with-def";
      expected = true;
    };
    import_dirWithDefIgnoresSiblings = {
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
      # root-default-sibling/default.nix exists → dir collapses to its import.
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

    # import — expandDir (opt-out of default.nix collapse)
    import_expandDirExposesDefaultAsKey = {
      expr = builtins.isFunction
        (nixliteImport { path = fix; expandDir = true; })."dir-with-def".default;
      expected = true;
    };
    import_expandDirExposesSiblings = {
      expr = (nixliteImport { path = fix; expandDir = true; })."dir-with-def".ignored;
      expected = { must = "be ignored when sibling default.nix exists"; };
    };
    import_expandDirRootDefaultSiblingWalked = {
      expr = (nixliteImport { path = fix; expandDir = true; }).root-default-sibling;
      expected = { default = { collapsed = true; }; };
    };

    # import — flatten (single path)
    import_flattenSinglePath = {
      expr = nixliteImport { path = flat; flatten = true; };
      expected = [ { a = 1; } { b = 2; } { c = 3; } ];
    };
    import_flattenCollapseDirLength = {
      # dir-with-def has default.nix → flat walk treats it as one leaf.
      expr = builtins.length
        (nixliteImport { path = fix + "/dir-with-def"; flatten = true; });
      expected = 1;
    };
    import_flattenCollapseDirFirstIsFunction = {
      expr = builtins.isFunction
        (builtins.head (nixliteImport { path = fix + "/dir-with-def"; flatten = true; }));
      expected = true;
    };
    import_flattenWithExpandDir = {
      # With expandDir, dir-with-def walks and produces 2 values in order.
      expr = nixliteImport {
        path = fix + "/dir-with-def";
        flatten = true;
        expandDir = true;
        resolve = { tag = "F"; };
      };
      expected = [
        { dirFn = { tag = "F"; }; }
        { must = "be ignored when sibling default.nix exists"; }
      ];
    };
    import_flattenWithResolveNoOp = {
      expr = nixliteImport {
        path = flat;
        flatten = true;
        resolve = { tag = "F"; };
      };
      # No functions in fixtures-flat, so resolve is a no-op.
      expected = [ { a = 1; } { b = 2; } { c = 3; } ];
    };

    # import — list-of-paths at top level (implicit flatten)
    import_listShorthandFiles = {
      expr = nixliteImport [ (flat + "/a.nix") (flat + "/b.nix") ];
      expected = [ { a = 1; } { b = 2; } ];
    };
    import_listShorthandDirs = {
      expr = nixliteImport [ flat ];
      expected = [ { a = 1; } { b = 2; } { c = 3; } ];
    };
    import_listShorthandMixed = {
      expr = nixliteImport [ (flat + "/a.nix") (flat + "/sub") ];
      expected = [ { a = 1; } { c = 3; } ];
    };
    import_listShorthandCollapseLen = {
      # Each collapsing dir contributes exactly one element.
      expr = builtins.length
        (nixliteImport [ (fix + "/dir-with-def") (fix + "/root-default-sibling") ]);
      expected = 2;
    };

    # import — list-of-paths via attrset form
    import_listAttrsFormFiles = {
      expr = nixliteImport { path = [ (flat + "/a.nix") (flat + "/b.nix") ]; };
      expected = [ { a = 1; } { b = 2; } ];
    };
    import_listAttrsFormWithResolve = {
      expr = nixliteImport {
        path = [ (fix + "/dir-with-def") ];
        resolve = { tag = "R"; };
      };
      expected = [ { dirFn = { tag = "R"; }; } ];
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
    import_throwsBadPathType = {
      expr = throws (nixliteImport { path = "str"; });
      expected = true;
    };
    import_throwsListWithNonPathElement = {
      expr = throws (nixliteImport [ flat "str" ]);
      expected = true;
    };
    import_throwsListAttrsWithNonPathElement = {
      expr = throws (nixliteImport { path = [ flat "str" ]; });
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
