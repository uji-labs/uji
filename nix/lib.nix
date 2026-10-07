# Helpers for modules that give a plugin typed options in programs.uji. The
# home-manager module passes them to every module as `ujiLib`; the flake
# exports them as `lib`.
{ lib }:

{
  # The option for one plugin: `enable`, and `settings` for its
  # `require(name).setup(settings)`. `settings` accepts any key; the ones in
  # `settings` here are checked and documented.
  mkPlugin =
    {
      description,
      settings ? { },
    }:
    lib.mkOption {
      default = { };
      description = "The ${description} plugin.";
      type = lib.types.submodule {
        options = {
          enable = lib.mkEnableOption description;
          settings = lib.mkOption {
            default = { };
            description = "Passed to the plugin's `setup`. Null values are left out.";
            type = lib.types.submodule {
              freeformType = lib.types.attrsOf lib.types.anything;
              options = settings;
            };
          };
        };
      };
    };

  # A setting that is left out until it's set, so the plugin's own default
  # applies; `default` is only shown in the documentation (null shows none).
  mkSetting =
    type: default: description:
    lib.mkOption {
      type = lib.types.nullOr type;
      default = null;
      description =
        description
        +
          lib.optionalString (default != null)
            " The plugin's default is `${lib.generators.toPretty { multiline = false; } default}`.";
    };
}
