{ pkgs, ... }:

{
  packages = with pkgs; [
    # Testing frameworks
    (bats.withLibraries (p: [
      p.bats-support
      p.bats-assert
    ]))
    k6
    playwright-driver
  ];

  env.PLAYWRIGHT_BROWSERS_PATH = "${pkgs.playwright-driver.browsers}";
  env.PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
}
