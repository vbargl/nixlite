{ lib, nixlite }:
let
  inherit (nixlite) eval;

  # Deep-force the value so tryEval catches throws buried in lazy attrs
  # (same reason as tests/default.nix).
  throws = e: !(builtins.tryEval (builtins.deepSeq e null)).success;

  modA = ./eval-fixtures/mod-a.nix;
  modList = ./eval-fixtures/mod-list.nix;
  modFn = ./eval-fixtures/mod-fn.nix;
  modRetPath = ./eval-fixtures/mod-ret-path.nix;
in
{
  # ── attrset root ─────────────────────────────────────────────────────
  eval_rootAttrset = {
    expr = eval { module = { a = 1; }; };
    expected = { a = 1; };
  };
  eval_rootAttrsetWithImports = {
    expr = eval { module = { imports = [ { a = 1; } { b = 2; } ]; c = 3; }; };
    expected = { a = 1; b = 2; c = 3; };
  };
  eval_importsStrippedFromResult = {
    expr = (eval { module = { imports = [ ]; x = 1; }; }) ? imports;
    expected = false;
  };
  eval_nestedImports = {
    expr = eval {
      module = {
        imports = [
          {
            imports = [ { deep = 1; } ];
            mid = 2;
          }
        ];
        top = 3;
      };
    };
    expected = { deep = 1; mid = 2; top = 3; };
  };

  # ── list root ────────────────────────────────────────────────────────
  eval_rootList = {
    expr = eval { module = [ { a = 1; } { b = 2; } ]; };
    expected = { a = 1; b = 2; };
  };
  eval_listOfLists = {
    expr = eval { module = [ [ { a = 1; } ] [ { b = 2; } ] ]; };
    expected = { a = 1; b = 2; };
  };
  eval_listWithFunction = {
    expr = eval {
      inputs = { tag = "R"; };
      module = [ ({ self, tag }: { fn = tag; }) ];
    };
    expected = { fn = "R"; };
  };

  # ── function root ────────────────────────────────────────────────────
  eval_rootFunction = {
    expr = eval {
      inputs = { tag = "R"; };
      module = { self, tag }: { fn = tag; };
    };
    expected = { fn = "R"; };
  };
  eval_inputsDefaultEmpty = {
    expr = eval { module = { self, ... }: { ok = true; }; };
    expected = { ok = true; };
  };
  eval_selfFixpoint = {
    expr = eval {
      module = [
        { a = 5; }
        ({ self, ... }: { double = self.a * 2; })
      ];
    };
    expected = { a = 5; double = 10; };
  };
  eval_inputsSpreadFlat = {
    expr = eval {
      inputs = { flake = "F"; };
      module = { self, flake }: { got = flake; };
    };
    expected = { got = "F"; };
  };

  # ── paths (inside lists) ─────────────────────────────────────────────
  eval_pathInList = {
    expr = eval { module = [ modA ]; };
    expected = { a = 1; };
  };
  eval_pathInImports = {
    expr = eval { module = { imports = [ modA ]; b = 2; }; };
    expected = { a = 1; b = 2; };
  };
  eval_pathDedup = {
    expr = eval { module = [ modList modList ]; };
    expected = { items = [ "x" ]; };
  };
  eval_pathFunction = {
    expr = eval {
      inputs = { tag = "X"; };
      module = [ modFn ];
    };
    expected = { fn = "X"; };
  };

  # ── errors ───────────────────────────────────────────────────────────
  eval_throwsBarePath = {
    expr = throws (eval { module = modA; });
    expected = true;
  };
  eval_throwsIntInList = {
    expr = throws (eval { module = [ 1 ]; });
    expected = true;
  };
  eval_throwsInputsWithSelf = {
    expr = throws (eval { inputs = { self = 1; }; module = { }; });
    expected = true;
  };
  eval_throwsImportsNotList = {
    expr = throws (eval { module = { imports = 1; }; });
    expected = true;
  };
  eval_throwsUnknownKey = {
    expr = throws (eval { module = { }; bogus = 1; });
    expected = true;
  };
  eval_throwsMissingModule = {
    expr = throws (eval { inputs = { }; });
    expected = true;
  };
  eval_throwsBadArg = {
    expr = throws (eval "oops");
    expected = true;
  };
  eval_throwsMergeConflict = {
    expr = throws (eval { module = [ { a = 1; } { a = 2; } ]; });
    expected = true;
  };
  eval_throwsFunctionReturnsPath = {
    expr = throws (eval { module = ({ self, ... }: modA); });
    expected = true;
  };
  eval_throwsImportsFunctionReturnsPath = {
    expr = throws (eval {
      module = { imports = [ ({ self, ... }: modA) ]; };
    });
    expected = true;
  };
  eval_throwsPathFileReturnsPath = {
    # modRetPath's contents are `./mod-a.nix`, so importing it yields another
    # path — that result is not allowed to be a path.
    expr = throws (eval { module = [ modRetPath ]; });
    expected = true;
  };

  # ── imports can contain every in-list shape ──────────────────────────
  eval_importsMixed = {
    expr = eval {
      inputs = { tag = "T"; };
      module = {
        imports = [
          modA
          { b = 2; }
          ({ self, tag }: { c = tag; })
          [ { d = 4; } ]
        ];
        e = 5;
      };
    };
    expected = { a = 1; b = 2; c = "T"; d = 4; e = 5; };
  };
}
