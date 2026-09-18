fn main() {
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("macos") { return; }
    println!("cargo:rerun-if-changed=src/composer_glass.m");
    let out = std::path::PathBuf::from(std::env::var_os("OUT_DIR").unwrap());
    let object = out.join("composer_glass.o");
    assert!(std::process::Command::new("xcrun").args(["clang", "-fobjc-arc", "-fmodules", "-mmacosx-version-min=14.0", "-c", "src/composer_glass.m", "-o"]).arg(&object).status().unwrap().success());
    let archive = out.join("libcomposer_glass.a");
    assert!(std::process::Command::new("ar").arg("crs").arg(&archive).arg(object).status().unwrap().success());
    println!("cargo:rustc-link-search=native={}", out.display());
    println!("cargo:rustc-link-lib=static=composer_glass");
    println!("cargo:rustc-link-lib=framework=AppKit");
}
