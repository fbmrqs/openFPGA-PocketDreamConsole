use plugin::roms::{profiles, run, transform, Action, Profile};
use sha1::{Digest, Sha1};
use sha2::Sha256;
use std::fs;
use std::io::{self, Read, Write};
use std::path::Path;

fn profile(source: &[u8], output: &[u8]) -> Profile {
    Profile {
        key: "demo".into(),
        label: "Demo".into(),
        source_size: source.len() as u64,
        source_sha1: format!("{:x}", Sha1::digest(source)),
        output_size: output.len() as u64,
        output_sha256: format!("{:x}", Sha256::digest(output)),
    }
}

fn card() -> tempfile::TempDir {
    let card = tempfile::tempdir().unwrap();
    let core = card.path().join("Cores/fbmrqs.PocketDreamConsole");
    fs::create_dir_all(&core).unwrap();
    fs::write(
        core.join("core.json"),
        br#"{"core":{"metadata":{"author":"fbmrqs","shortname":"PocketDreamConsole"}}}"#,
    )
    .unwrap();
    fs::create_dir_all(card.path().join("Assets/pdc/import")).unwrap();
    card
}

fn prepare(card: &Path, profile: &Profile) -> plugin::roms::Summary {
    run(
        card,
        std::slice::from_ref(profile),
        Action::Prepare,
        &mut |_| {},
    )
    .unwrap()
}

#[test]
fn zero_padding_and_unchanged_images_match_literal_outputs() {
    for (mut source, expected) in [
        (b"abc".as_slice(), b"abc\0\0\0".as_slice()),
        (b"same".as_slice(), b"same".as_slice()),
    ] {
        let mut output = Vec::new();
        let p = profile(source, expected);
        transform(&mut source, &mut output, &p).unwrap();
        assert_eq!(output, expected);
    }
}

#[test]
fn unknown_same_size_data_is_rejected_without_publishing_a_rom() {
    let card = card();
    fs::write(card.path().join("Assets/pdc/import/unknown.bin"), b"bad").unwrap();
    assert_eq!(prepare(card.path(), &profile(b"abc", b"abc")).rejected, 1);
    assert!(!card.path().join("Assets/pdc/common/demo.rom").exists());
}

#[test]
fn input_reads_are_bounded_even_if_a_decoder_never_reaches_eof() {
    struct Endless;
    impl Read for Endless {
        fn read(&mut self, out: &mut [u8]) -> io::Result<usize> {
            out.fill(b'a');
            Ok(out.len())
        }
    }
    let mut output = Vec::new();
    assert!(transform(&mut Endless, &mut output, &profile(b"abc", b"abc")).is_err());
    assert!(output.len() <= 3);
}

#[test]
fn repeated_runs_keep_correct_files_and_refuse_conflicting_files() {
    let card = card();
    let p = profile(b"abc", b"abc\0");
    fs::write(card.path().join("Assets/pdc/import/source.bin"), b"abc").unwrap();
    assert_eq!(prepare(card.path(), &p).prepared, 1);
    assert_eq!(prepare(card.path(), &p).correct, 1);
    let dest = card.path().join("Assets/pdc/common/demo.rom");
    fs::write(&dest, b"keep-me").unwrap();
    assert_eq!(prepare(card.path(), &p).failed, 1);
    assert_eq!(fs::read(dest).unwrap(), b"keep-me");
}

#[test]
fn archive_member_paths_never_control_output_paths() {
    let card = card();
    let path = card.path().join("Assets/pdc/import/input.zip");
    let mut zip = zip::ZipWriter::new(fs::File::create(&path).unwrap());
    zip.start_file(
        "../../outside.bin",
        zip::write::SimpleFileOptions::default()
            .compression_method(zip::CompressionMethod::Deflated),
    )
    .unwrap();
    zip.write_all(b"abc").unwrap();
    zip.finish().unwrap();
    assert_eq!(prepare(card.path(), &profile(b"abc", b"abc")).prepared, 1);
    assert_eq!(
        fs::read(card.path().join("Assets/pdc/common/demo.rom")).unwrap(),
        b"abc"
    );
    assert!(!card.path().join("outside.bin").exists());
    assert!(!card.path().join("Assets/pdc/outside.bin").exists());
}

#[test]
fn a_corrupt_zip_is_reported_without_any_final_output() {
    let card = card();
    fs::write(card.path().join("Assets/pdc/import/bad.zip"), b"PKbroken").unwrap();
    assert_eq!(prepare(card.path(), &profile(b"abc", b"abc")).failed, 1);
    assert!(!card.path().join("Assets/pdc/common/demo.rom").exists());
}

#[test]
fn a_raw_dump_is_recognized_even_when_its_name_ends_in_zip() {
    let card = card();
    fs::write(card.path().join("Assets/pdc/import/renamed.zip"), b"abc").unwrap();
    assert_eq!(prepare(card.path(), &profile(b"abc", b"abc")).prepared, 1);
}

#[test]
fn changing_only_the_unused_half_still_invalidates_the_original_dump() {
    let mut output = Vec::new();
    assert!(transform(
        &mut b"active-broken".as_slice(),
        &mut output,
        &profile(b"active-unused", b"active")
    )
    .is_err());
}

#[test]
fn a_zip_with_valid_rom_bytes_but_a_bad_archive_crc_is_rejected() {
    let card = card();
    let path = card.path().join("Assets/pdc/import/bad-crc.zip");
    let mut zip = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
    zip.start_file(
        "source.bin",
        zip::write::SimpleFileOptions::default().compression_method(zip::CompressionMethod::Stored),
    )
    .unwrap();
    zip.write_all(b"abc").unwrap();
    let mut bytes = zip.finish().unwrap().into_inner();
    let central = bytes.windows(4).position(|w| w == b"PK\x01\x02").unwrap();
    bytes[central + 16] ^= 1;
    fs::write(&path, bytes).unwrap();
    let result = prepare(card.path(), &profile(b"abc", b"abc"));
    assert_eq!(result.failed + result.rejected, 1);
    assert!(!card.path().join("Assets/pdc/common/demo.rom").exists());
}

#[test]
fn an_interrupted_run_requires_explicit_cleanup_and_can_then_be_retried() {
    let card = card();
    let output = card.path().join("Assets/pdc/common");
    fs::create_dir_all(&output).unwrap();
    fs::write(output.join(".pdc-import-demo.part"), b"interrupted").unwrap();
    fs::write(output.join("unrelated.part"), b"keep").unwrap();
    fs::write(card.path().join("Assets/pdc/import/source.bin"), b"abc").unwrap();
    let p = profile(b"abc", b"abc");
    assert_eq!(prepare(card.path(), &p).failed, 1);
    assert_eq!(
        fs::read(output.join(".pdc-import-demo.part")).unwrap(),
        b"interrupted"
    );
    assert_eq!(
        run(
            card.path(),
            std::slice::from_ref(&p),
            Action::Clean,
            &mut |_| {}
        )
        .unwrap()
        .cleaned,
        1
    );
    assert_eq!(fs::read(output.join("unrelated.part")).unwrap(), b"keep");
    assert_eq!(prepare(card.path(), &p).prepared, 1);
}

#[test]
fn a_destination_created_during_preparation_is_not_overwritten() {
    let card = card();
    let dest = card.path().join("Assets/pdc/common/demo.rom");
    fs::write(card.path().join("Assets/pdc/import/source.bin"), b"abc").unwrap();
    let result = run(
        card.path(),
        &[profile(b"abc", b"abc")],
        Action::Prepare,
        &mut |line| {
            if line.starts_with("Preparing ") {
                fs::write(&dest, b"someone-else").unwrap();
            }
        },
    )
    .unwrap();
    assert_eq!(result.failed, 1);
    assert_eq!(fs::read(&dest).unwrap(), b"someone-else");
    assert!(!dest
        .parent()
        .unwrap()
        .join(".pdc-import-demo.part")
        .exists());
}

#[test]
fn a_missing_core_does_not_create_any_card_files() {
    let card = tempfile::tempdir().unwrap();
    assert!(run(
        card.path(),
        &profiles().unwrap(),
        Action::Prepare,
        &mut |_| {}
    )
    .is_err());
    assert_eq!(fs::read_dir(card.path()).unwrap().count(), 0);
}

#[cfg(unix)]
#[test]
fn symlinks_cannot_redirect_output_or_cleanup_outside_the_card() {
    use std::os::unix::fs::symlink;
    let card = card();
    let outside = tempfile::tempdir().unwrap();
    symlink(outside.path(), card.path().join("Assets/pdc/common")).unwrap();
    assert!(run(
        card.path(),
        &[profile(b"abc", b"abc")],
        Action::Prepare,
        &mut |_| {}
    )
    .is_err());
    assert_eq!(fs::read_dir(outside.path()).unwrap().count(), 0);
}

#[test]
fn check_explains_a_raw_pdc100_misnamed_as_the_prepared_rom() {
    let card = card();
    let output = card.path().join("Assets/pdc/common");
    fs::create_dir_all(&output).unwrap();
    fs::File::create(output.join("pdc100.rom"))
        .unwrap()
        .set_len(134217728)
        .unwrap();
    let mut messages = Vec::new();
    let result = run(card.path(), &profiles().unwrap(), Action::Check, &mut |s| {
        messages.push(s.to_string())
    })
    .unwrap();
    assert_eq!(result.failed, 1);
    assert!(messages
        .iter()
        .any(|s| s.contains("128 MiB raw dump") && s.contains("64 MiB")));
    assert_eq!(
        fs::metadata(output.join("pdc100.rom")).unwrap().len(),
        134217728
    );
}
