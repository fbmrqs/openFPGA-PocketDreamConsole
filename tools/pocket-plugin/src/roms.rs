use serde::Deserialize;
use sha1::{Digest, Sha1};
use sha2::Sha256;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::io::{Seek, SeekFrom};
use std::path::Path;
use std::path::PathBuf;

const CORE: &str = "Cores/fbmrqs.PocketDreamConsole";
const INPUT: &str = "Assets/pdc/import";
const OUTPUT: &str = "Assets/pdc/common";
const MAX_SOURCE: u64 = 128 * 1024 * 1024;
const RESERVE: u64 = 16 * 1024 * 1024;

#[derive(Clone, Copy)]
pub enum Action {
    Prepare,
    Check,
    Clean,
}

#[derive(Default, Debug)]
pub struct Summary {
    pub prepared: usize,
    pub correct: usize,
    pub rejected: usize,
    pub failed: usize,
    pub missing: usize,
    pub cleaned: usize,
}

pub fn profiles() -> io::Result<Vec<Profile>> {
    let profiles: Vec<Profile> = serde_json::from_str(include_str!("../profiles.json"))?;
    for p in &profiles {
        if p.key.is_empty()
            || !p
                .key
                .bytes()
                .all(|c| c.is_ascii_alphanumeric() || c == b'_')
            || p.source_size == 0
            || p.source_size > MAX_SOURCE
            || p.output_size == 0
            || p.output_size > 64 * 1024 * 1024
            || p.source_sha1.len() != 40
            || p.output_sha256.len() != 64
            || !p
                .source_sha1
                .bytes()
                .chain(p.output_sha256.bytes())
                .all(|b| b.is_ascii_hexdigit())
        {
            return Err(io::Error::other("invalid compiled profile data"));
        }
    }
    Ok(profiles)
}

fn directory(card: &Path, relative: &str, create: bool) -> io::Result<PathBuf> {
    let mut path = card.to_path_buf();
    for component in Path::new(relative) {
        path.push(component);
        match fs::symlink_metadata(&path) {
            Ok(m) if m.is_dir() && !m.file_type().is_symlink() => (),
            Ok(_) => {
                return Err(io::Error::other(format!(
                    "not a regular directory: {relative}"
                )))
            }
            Err(e) if e.kind() == io::ErrorKind::NotFound => {
                if create {
                    fs::create_dir(&path)?;
                }
            }
            Err(e) => return Err(e),
        }
    }
    Ok(path)
}

fn regular(path: &Path) -> io::Result<Option<fs::Metadata>> {
    match fs::symlink_metadata(path) {
        Ok(m) if m.is_file() && !m.file_type().is_symlink() => Ok(Some(m)),
        Ok(_) => Err(io::Error::other(format!(
            "not a regular file: {}",
            path.display()
        ))),
        Err(e) if e.kind() == io::ErrorKind::NotFound => Ok(None),
        Err(e) => Err(e),
    }
}

fn hash_reader<D: Digest + Default>(
    source: &mut dyn Read,
    limit: u64,
) -> io::Result<(u64, String)> {
    let mut hash = D::default();
    let mut buffer = vec![0; 1024 * 1024];
    let mut size = 0;
    loop {
        let count = source.read(&mut buffer[..((limit - size + 1).min(1024 * 1024)) as usize])?;
        if count == 0 {
            break;
        }
        size += count as u64;
        if size > limit {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "input exceeds supported size",
            ));
        }
        hash.update(&buffer[..count]);
    }
    let hex = hash.finalize().iter().map(|b| format!("{b:02x}")).collect();
    Ok((size, hex))
}

fn matches_output(path: &Path, profile: &Profile) -> io::Result<bool> {
    match regular(path)? {
        Some(m) if m.len() == profile.output_size => {
            let (size, hash) = hash_reader::<Sha256>(&mut File::open(path)?, profile.output_size)?;
            Ok(size == profile.output_size && hash == profile.output_sha256)
        }
        _ => Ok(false),
    }
}

#[derive(Clone)]
struct Input {
    path: PathBuf,
    member: Option<usize>,
    size: u64,
    shown: String,
}

impl Input {
    fn read<T>(&self, use_reader: impl FnOnce(&mut dyn Read) -> io::Result<T>) -> io::Result<T> {
        regular(&self.path)?.ok_or_else(|| io::Error::other("source disappeared"))?;
        let mut file = File::open(&self.path)?;
        match self.member {
            None => use_reader(&mut file),
            Some(index) => {
                let mut archive = zip::ZipArchive::new(file).map_err(io::Error::other)?;
                let mut member = archive.by_index(index).map_err(io::Error::other)?;
                if member.size() != self.size {
                    return Err(io::Error::other("ZIP changed during preparation"));
                }
                use_reader(&mut member)
            }
        }
    }
}

fn collect(folder: &Path, depth: usize, paths: &mut Vec<PathBuf>) -> io::Result<()> {
    if depth > 16 || paths.len() > 4096 {
        return Err(io::Error::other("input folder exceeds scan limits"));
    }
    for entry in fs::read_dir(folder)? {
        let entry = entry?;
        if entry.file_name().to_string_lossy().starts_with('.') {
            continue;
        }
        let kind = entry.file_type()?;
        if kind.is_dir() {
            collect(&entry.path(), depth + 1, paths)?;
        } else if kind.is_file() {
            if paths.len() >= 4096 {
                return Err(io::Error::other("input folder exceeds scan limits"));
            }
            paths.push(entry.path());
        }
    }
    Ok(())
}

fn inputs(path: &Path, profiles: &[Profile]) -> io::Result<Vec<Input>> {
    let size = regular(path)?
        .ok_or_else(|| io::Error::other("missing input"))?
        .len();
    let shown = path
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .into_owned();
    let mut signature = [0; 4];
    let count = File::open(path)?.read(&mut signature)?;
    let archive_named = path
        .extension()
        .is_some_and(|e| e.eq_ignore_ascii_case("zip"))
        || (count == 4 && signature.starts_with(b"PK"));
    match zip::ZipArchive::new(File::open(path)?) {
        Ok(mut zip) => {
            if zip.len() > 4096 {
                return Err(io::Error::other("ZIP contains too many members"));
            }
            let mut found = Vec::new();
            for index in 0..zip.len() {
                let member = zip.by_index(index).map_err(io::Error::other)?;
                if !member.is_dir() && profiles.iter().any(|p| p.source_size == member.size()) {
                    found.push(Input {
                        path: path.to_path_buf(),
                        member: Some(index),
                        size: member.size(),
                        shown: format!("{shown}: {}", member.name().map_err(io::Error::other)?),
                    });
                }
            }
            Ok(found)
        }
        Err(error) if archive_named && !profiles.iter().any(|p| p.source_size == size) => {
            Err(io::Error::other(error))
        }
        Err(_) => Ok(vec![Input {
            path: path.to_path_buf(),
            member: None,
            size,
            shown,
        }]),
    }
}

fn prepare(
    input: &Input,
    profiles: &[Profile],
    output: &Path,
    log: &mut dyn FnMut(&str),
) -> io::Result<bool> {
    if !profiles.iter().any(|p| p.source_size == input.size) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("unsupported raw size: {} bytes", input.size),
        ));
    }
    log(&format!(
        "Checking {} ({} bytes)...",
        input.shown, input.size
    ));
    let (size, sha1) = input.read(|r| hash_reader::<Sha1>(r, input.size))?;
    let profile = profiles
        .iter()
        .find(|p| p.source_size == size && p.source_sha1 == sha1)
        .ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                format!("unrecognized dump (SHA-1 {sha1}); use a supported revision"),
            )
        })?;
    let dest = output.join(format!("{}.rom", profile.key));
    if matches_output(&dest, profile)? {
        log(&format!("Already correct: {}.rom", profile.key));
        return Ok(false);
    }
    if regular(&dest)?.is_some() {
        return Err(io::Error::other(format!("Existing {}.rom differs. Preserve/move it to Assets/pdc/import before preparing; it will not be overwritten.", profile.key)));
    }
    let temp = output.join(format!(".pdc-import-{}.part", profile.key));
    let mut file = OpenOptions::new().read(true).write(true).create_new(true).open(&temp)
        .map_err(|e| io::Error::other(format!("Cannot start {}: {e}. For an interrupted run, use Remove unfinished imports only when no other updater is running.", profile.key)))?;
    let result = (|| {
        // FAT/exFAT allocate this reservation; actual writes remain checked on sparse filesystems.
        file.set_len(profile.output_size + RESERVE)?;
        log(&format!(
            "Preparing {}: {} -> {} bytes...",
            profile.label, profile.source_size, profile.output_size
        ));
        input.read(|r| transform(r, &mut file, profile))?;
        file.set_len(profile.output_size)?;
        file.sync_all()?;
        file.seek(SeekFrom::Start(0))?;
        let (size, hash) = hash_reader::<Sha256>(&mut file, profile.output_size)?;
        if size != profile.output_size || hash != profile.output_sha256 {
            return Err(io::Error::other("output read-back verification failed"));
        }
        Ok(())
    })();
    drop(file);
    let result = result.and_then(|_| {
        if regular(&dest)?.is_some() {
            return Err(io::Error::other(
                "destination appeared during import; no replacement made",
            ));
        }
        fs::rename(&temp, &dest)?;
        log(&format!("Verified {}.rom", profile.key));
        Ok(true)
    });
    if result.is_err() {
        let _ = fs::remove_file(&temp);
    }
    result
}

pub fn run(
    card: &Path,
    profiles: &[Profile],
    action: Action,
    log: &mut dyn FnMut(&str),
) -> io::Result<Summary> {
    let core = directory(card, CORE, false)?.join("core.json");
    regular(&core)?.ok_or_else(|| {
        io::Error::other("Install fbmrqs.PocketDreamConsole before running this plugin.")
    })?;
    let definition: serde_json::Value = serde_json::from_reader(File::open(core)?)?;
    if definition["core"]["metadata"]["author"] != "fbmrqs"
        || definition["core"]["metadata"]["shortname"] != "PocketDreamConsole"
    {
        return Err(io::Error::other(
            "core identity does not match fbmrqs.PocketDreamConsole",
        ));
    }
    let output = directory(card, OUTPUT, matches!(action, Action::Prepare))?;
    let mut result = Summary::default();
    match action {
        Action::Check => {
            for p in profiles {
                let path = output.join(format!("{}.rom", p.key));
                match regular(&path) {
                    Ok(None) => {
                        result.missing += 1;
                        log(&format!("Not installed: {}.rom", p.key));
                    }
                    Ok(Some(m)) if p.key == "pdc100" && m.len() == 134217728 => {
                        result.failed += 1;
                        log("pdc100.rom is the 128 MiB raw dump. Move it to Assets/pdc/import, then run the plugin to create the required 64 MiB file.");
                    }
                    Ok(Some(_)) => match matches_output(&path, p) {
                        Ok(true) => {
                            result.correct += 1;
                            log(&format!("Correct: {}.rom", p.key));
                        }
                        _ => {
                            result.failed += 1;
                            log(&format!("Invalid {}.rom: size/hash differs; preserve it and prepare a supported original.", p.key));
                        }
                    },
                    Err(e) => {
                        result.failed += 1;
                        log(&e.to_string());
                    }
                }
            }
        }
        Action::Clean => {
            for p in profiles {
                let path = output.join(format!(".pdc-import-{}.part", p.key));
                if regular(&path)?.is_some() {
                    fs::remove_file(path)?;
                    result.cleaned += 1;
                }
            }
        }
        Action::Prepare => {
            let input = directory(card, INPUT, true)?;
            let mut paths = Vec::new();
            collect(&input, 0, &mut paths)?;
            paths.sort();
            if paths.is_empty() {
                log("No input files. Put your supported raw dumps or ZIPs in Assets/pdc/import, then run the plugin again.");
            }
            for path in paths {
                match inputs(&path, profiles) {
                    Ok(sources) if sources.is_empty() => {
                        result.rejected += 1;
                        log(&format!("No supported dump sizes in {}", path.display()));
                    }
                    Ok(sources) => {
                        for source in sources {
                            match prepare(&source, profiles, &output, log) {
                                Ok(true) => result.prepared += 1,
                                Ok(false) => result.correct += 1,
                                Err(e) => {
                                    if e.kind() == io::ErrorKind::InvalidData {
                                        result.rejected += 1;
                                    } else {
                                        result.failed += 1;
                                    }
                                    log(&format!("{}: {e}", source.shown));
                                }
                            }
                        }
                    }
                    Err(e) => {
                        result.failed += 1;
                        log(&format!("{}: {e}", path.display()));
                    }
                }
            }
        }
    }
    log(&format!("Summary: {} prepared, {} already correct, {} not installed, {} rejected, {} failed, {} unfinished files removed.", result.prepared, result.correct, result.missing, result.rejected, result.failed, result.cleaned));
    Ok(result)
}

#[derive(Clone, Debug, Deserialize)]
pub struct Profile {
    pub key: String,
    pub label: String,
    pub source_size: u64,
    pub source_sha1: String,
    pub output_size: u64,
    pub output_sha256: String,
}

pub fn transform(
    source: &mut dyn Read,
    output: &mut dyn Write,
    profile: &Profile,
) -> io::Result<()> {
    let mut buffer = vec![0; 1024 * 1024];
    let (mut original, mut prepared) = (Sha1::new(), Sha256::new());
    let (mut read, mut written) = (0, 0);
    loop {
        let limit =
            (profile.source_size.saturating_sub(read) + 1).min(buffer.len() as u64) as usize;
        let count = source.read(&mut buffer[..limit])?;
        if count == 0 {
            break;
        }
        read += count as u64;
        if read > profile.source_size {
            return Err(io::Error::other("source exceeds supported size"));
        }
        original.update(&buffer[..count]);
        let used = (profile.output_size - written).min(count as u64) as usize;
        output.write_all(&buffer[..used])?;
        prepared.update(&buffer[..used]);
        written += used as u64;
    }
    if read != profile.source_size || format!("{:x}", original.finalize()) != profile.source_sha1 {
        return Err(io::Error::other(
            "source size/hash does not match a supported dump",
        ));
    }
    buffer.fill(0);
    while written < profile.output_size {
        let count = (profile.output_size - written).min(buffer.len() as u64) as usize;
        output.write_all(&buffer[..count])?;
        prepared.update(&buffer[..count]);
        written += count as u64;
    }
    if format!("{:x}", prepared.finalize()) != profile.output_sha256 {
        return Err(io::Error::other(
            "prepared hash differs from the verified reference",
        ));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use sha1::{Digest, Sha1};
    use sha2::Sha256;

    fn fixture(source: &[u8], expected: &[u8]) -> Profile {
        Profile {
            key: "demo".into(),
            label: "Demo".into(),
            source_size: source.len() as u64,
            source_sha1: format!("{:x}", Sha1::digest(source)),
            output_size: expected.len() as u64,
            output_sha256: format!("{:x}", Sha256::digest(expected)),
        }
    }

    #[test]
    fn prepares_only_the_used_prefix_and_preserves_the_source() {
        let original = b"active-unused";
        let mut output = Vec::new();
        transform(
            &mut original.as_slice(),
            &mut output,
            &fixture(original, b"active"),
        )
        .unwrap();
        assert_eq!(output, b"active");
        assert_eq!(original, b"active-unused");
    }

    #[test]
    fn prepares_a_local_dump_into_the_core_directory_without_changing_originals() {
        let card = tempfile::tempdir().unwrap();
        let core = card.path().join("Cores/fbmrqs.PocketDreamConsole");
        std::fs::create_dir_all(&core).unwrap();
        std::fs::write(
            core.join("core.json"),
            br#"{"core":{"metadata":{"author":"fbmrqs","shortname":"PocketDreamConsole"}}}"#,
        )
        .unwrap();
        let input = card.path().join("Assets/pdc/import");
        std::fs::create_dir_all(&input).unwrap();
        std::fs::write(input.join("renamed.u2"), b"active-unused").unwrap();
        let result = run(
            card.path(),
            &[fixture(b"active-unused", b"active")],
            Action::Prepare,
            &mut |_| {},
        )
        .unwrap();
        assert_eq!(result.prepared, 1);
        assert_eq!(
            std::fs::read(card.path().join("Assets/pdc/common/demo.rom")).unwrap(),
            b"active"
        );
        assert_eq!(
            std::fs::read(input.join("renamed.u2")).unwrap(),
            b"active-unused"
        );
    }
}
