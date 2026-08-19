{
  pkgs,
  lib,
  browserless ? false,
  ...
}:

{
  packages =
    with pkgs;
    [
      # Testing frameworks
      (bats.withLibraries (p: [
        p.bats-support
        p.bats-assert
      ]))
      k6
    ]
    ++ lib.optionals (!browserless) [
      playwright-driver
    ];

  env = {
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
  }
  // lib.optionalAttrs (!browserless) {
    PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
  };
}
