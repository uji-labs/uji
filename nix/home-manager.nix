# programs.uji for home-manager: writes ~/.config/uji from Nix, the way
# nixvim writes Neovim's config. The flake exports it as homeModules.default.
self:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.uji;
  ujiLib = import ./lib.nix { inherit lib; };
  inherit (lib) mkOption types;

  lua = lib.generators.toLua { };
  call = fn: args: "${fn}(${lib.concatMapStringsSep ", " lua args})";

  # store paths, such as a flake input, load as local packs
  pack = p: if lib.isStringLike p && lib.hasPrefix "/" "${p}" then { dir = "${p}"; } else p;

  keymaps = lib.concatLists (
    lib.mapAttrsToList (
      mode:
      lib.mapAttrsToList (
        key: action:
        if action == null then
          call "uji.keymap.remove" [
            mode
            key
          ]
        else
          call "uji.keymap.add" [
            mode
            key
            action
          ]
      )
    ) cfg.keymaps
  );

  setups = lib.mapAttrsToList (
    name: plugin:
    call "require(${lua name}).setup" [ (lib.filterAttrsRecursive (_: v: v != null) plugin.settings) ]
  ) (lib.filterAttrs (_: plugin: plugin.enable) cfg.plugins);
in
{
  options.programs.uji = {
    enable = lib.mkEnableOption "uji, the coding agent";

    package = mkOption {
      type = types.nullOr types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default or null;
      defaultText = lib.literalExpression "uji.packages.\${system}.default";
      description = "The uji package. Null writes only the config.";
    };

    defaults = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Start init.lua with uji's default config (`uji.builtin.defaults`),
        which a config of your own otherwise replaces.
      '';
    };

    toolPolicy = mkOption {
      type = types.attrsOf types.anything;
      default = { };
      example = {
        default = "allow";
        run_command.deny = [ ''/^\s*rm\s+-rf/'' ];
      };
      description = "Passed to `uji.tool.policy`.";
    };

    keymaps = mkOption {
      type = types.attrsOf (types.attrsOf types.anything);
      default = { };
      example = {
        normal."<C-p>".command = "models";
        normal."<C-u>" = "clear_input";
        normal."<C-c>" = null;
      };
      description = ''
        Keys per mode (normal, suggest, select, prompt, confirm, overlay): a
        builtin action name, `{ command = "..."; }` for a slash command, or
        null to unbind the key.
      '';
    };

    packs = mkOption {
      type = types.attrsOf (
        types.oneOf [
          types.path
          types.str
          (types.attrsOf types.anything)
        ]
      );
      default = { };
      example = lib.literalExpression ''
        {
          uji-plugins = inputs.uji-plugins;
          tool = "someone/tool";
          mine = { dir = "~/code/my-plugin"; };
        }
      '';
      description = ''
        Packs for `uji.pack.add`, by name. A store path or flake input loads
        as a local pack, so flake.lock pins it; strings and attribute sets are
        passed as they are.
      '';
    };

    plugins = mkOption {
      type = types.submodule {
        freeformType = types.attrsOf (ujiLib.mkPlugin { description = "named"; }).type;
      };
      default = { };
      example = {
        telescope = {
          enable = true;
          settings.editor = "nvim";
        };
      };
      description = ''
        `require(name).setup(settings)` for each enabled plugin. A pack's own
        module can give its plugins typed settings with `ujiLib.mkPlugin`.
      '';
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "Lua added to the end of init.lua.";
    };

    pluginFiles = mkOption {
      type = types.attrsOf types.lines;
      default = { };
      description = "Lua files for plugin/, which uji runs after init.lua in name order.";
    };
  };

  config = lib.mkMerge [
    # set even when uji is off, so pack modules can always declare options
    { _module.args.ujiLib = ujiLib; }

    (lib.mkIf cfg.enable {
      home.packages = lib.optional (cfg.package != null) cfg.package;

      xdg.configFile = {
        "uji/init.lua".text = lib.concatLines (
          lib.optional cfg.defaults ''require("uji.builtin.defaults")''
          ++ lib.optional (cfg.toolPolicy != { }) (call "uji.tool.policy" [ cfg.toolPolicy ])
          ++ keymaps
          ++ lib.optional (cfg.packs != { }) (call "uji.pack.add" [ (map pack (lib.attrValues cfg.packs)) ])
          ++ setups
          ++ lib.optional (cfg.extraConfig != "") cfg.extraConfig
        );
      }
      // lib.mapAttrs' (
        name: text: lib.nameValuePair "uji/plugin/${name}.lua" { inherit text; }
      ) cfg.pluginFiles;
    })
  ];
}
