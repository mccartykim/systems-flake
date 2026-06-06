{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.modules.fish-functions;

  jjPrompt = ''
    # Is jj installed?
    if not command -sq jj
        return 1
    end

    # Are we in a jj repo?
    if not jj root --quiet --no-pager &>/dev/null
        return 1
    end

    # Generate prompt
    jj log --ignore-working-copy --no-pager --no-graph --color always -r @ -T '
        surround(
            " (",
            ")",
            separate(
                " ",
                bookmarks.join(", "),
                coalesce(
                    surround(
                        "\"",
                        "\"",
                        if(
                            description.first_line().substr(0, 24).starts_with(description.first_line()),
                            description.first_line().substr(0, 24),
                            description.first_line().substr(0, 23) ++ "…"
                        )
                    ),
                    "(no desc)"
                ),
                change_id.shortest(),
                commit_id.shortest(),
                if(conflict, "(conflict)"),
                if(empty, "(empty)"),
                if(divergent, "(divergent)"),
                if(hidden, "(hidden)"),
            )
        )
    '
  '';

  vcsPrompt = ''
    # Override fish_vcs_prompt to prioritize jj over git
    function fish_vcs_prompt --description 'Print all vcs prompts'
        # If a prompt succeeded, we assume that it's printed the correct info.
        # This is so we don't try svn if git already worked.
        fish_jj_prompt $argv
        or fish_git_prompt $argv
        or fish_hg_prompt $argv
        or fish_fossil_prompt $argv
        # The svn prompt is disabled by default because it's quite slow on common svn repositories.
        # To enable it uncomment it.
        # You can also only use it in specific directories by checking $PWD.
        # or fish_svn_prompt
    end
  '';
in {
  options.modules.fish-functions = {
    enable = mkEnableOption "fish convenience functions";
    includeJjPrompt = mkEnableOption "jj VCS prompt functions (fish_jj_prompt, fish_vcs_prompt)";
  };

  config = mkIf cfg.enable {
    programs.fish.functions =
      {
        # -- jj shortcuts --
        # jd "msg" → jj desc -m "msg"
        jd = ''jj desc -m $argv'';

        # -- nix shortcuts --
        # nr hello → nix run nixpkgs#hello
        nr = ''nix run nixpkgs#$argv'';
        # ns hello → nix shell nixpkgs#hello
        ns = ''nix shell nixpkgs#$argv'';
        # nru lmstudio → NIXPKGS_ALLOW_UNFREE=1 nix run --impure nixpkgs#lmstudio
        nru = ''NIXPKGS_ALLOW_UNFREE=1 nix run --impure nixpkgs#$argv'';
        # nsu vscode → NIXPKGS_ALLOW_UNFREE=1 nix shell --impure nixpkgs#vscode
        nsu = ''NIXPKGS_ALLOW_UNFREE=1 nix shell --impure nixpkgs#$argv'';

        # cb file.txt → copy file contents to clipboard
        # cmd | cb → pipe stdin to clipboard
        cb = ''
          if test -n "$argv"
              cat $argv | fish_clipboard_copy
          else
              fish_clipboard_copy
          end
        '';
      }
      // optionalAttrs cfg.includeJjPrompt {
        fish_jj_prompt = jjPrompt;
        fish_vcs_prompt = vcsPrompt;
      };
  };
}