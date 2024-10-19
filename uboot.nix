{ buildUBoot
, fetchurl
, stdenv
, rkbin
}:

(buildUBoot rec {
  version = "2023.10";
  src = fetchurl {
    url = "https://ftp.denx.de/pub/u-boot/u-boot-${version}.tar.bz2";
    hash = "sha256-4A5sbwFOBGEBc50I0G8yiBHOvPWuEBNI9AnLvVXOaQA=";
  };
  defconfig = "nanopi-r5c-rk3568_defconfig";
  filesToInstall = ["u-boot.itb" "idbloader.img"];
}).override {
  patches = [ ];
  makeFlags = [
    "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
    "ROCKCHIP_TPL=${rkbin}/bin/rk35/rk3568_ddr_1560MHz_v1.18.bin"
    # FIXME: we can build bl31 from ATF
    "BL31=${rkbin}/bin/rk35/rk3568_bl31_v1.43.elf"
  ];
}
