use crate::roms::{self, Action};
use extism_pdk::*;
use serde::Deserialize;
use serde_json::{json, Value};
use std::path::Path;

const PREPARE: &str = "Prepare local ROMs";
const CHECK: &str = "Check installed ROMs";
const CLEAN: &str = "Remove unfinished imports";

#[derive(Deserialize)]
enum HostMessage {
    Answer { name: String, value: String },
    Kill,
}

#[host_fn]
extern "ExtismHost" {
    fn print_msg(message: &str) -> ();
}

fn log(message: &str) {
    unsafe {
        let _ = print_msg(&format!("{message}\n"));
    }
}

fn exit() -> FnResult<String> {
    Ok(serde_json::to_string(&Value::String("Exit".into()))?)
}

fn perform(action: Action) -> FnResult<String> {
    let result = (|| {
        let profiles = roms::profiles()?;
        let card = Path::new("pocket");
        if matches!(action, Action::Clean) {
            roms::run(card, &profiles, Action::Clean, &mut log)?;
        }
        let failed = if matches!(action, Action::Check) {
            0
        } else {
            log("Preparing local ROMs...");
            roms::run(card, &profiles, Action::Prepare, &mut log)?.failed
        };
        log("Checking installed ROMs...");
        roms::run(card, &profiles, Action::Check, &mut log)?;
        Ok::<_, std::io::Error>(failed)
    })();
    match result {
        Ok(failed) if failed > 0 => {
            return Ok(serde_json::to_string(&json!({"Choice": {
                "name": "action",
                "query": "Preparation failed; see the messages above. If an interrupted import left temporary files, cleanup and retry is available.",
                "choices": [CLEAN, "Exit"]
            }}))?);
        }
        Err(error) => log(&format!("Stopped: {error}")),
        _ => (),
    }
    exit()
}

#[plugin_fn]
pub fn start() -> FnResult<String> {
    log(concat!(
        "Pocket Dream Console ROM preparation ",
        env!("CARGO_PKG_VERSION")
    ));
    log("Offline only. Put supported raw dumps or ZIPs in Assets/pdc/import. Originals are preserved. Run only one updater against this card at a time.");
    perform(Action::Prepare)
}

#[plugin_fn]
pub fn handle_response(input: String) -> FnResult<String> {
    let message = match serde_json::from_str::<HostMessage>(&input) {
        Ok(message) => message,
        Err(_) => {
            log("Invalid response; nothing changed.");
            return exit();
        }
    };
    let action = match message {
        HostMessage::Kill => return exit(),
        HostMessage::Answer { name, value } if name == "action" && value == CLEAN => {
            return Ok(serde_json::to_string(&json!({"Choice": {
                "name": "cleanup",
                "query": "Only continue if no other updater is running. Remove this plugin's unfinished temporary imports? Original dumps and final ROMs are kept.",
                "choices": ["Cancel", CLEAN]
            }}))?);
        }
        HostMessage::Answer { name, value } if name == "action" && value == PREPARE => {
            Action::Prepare
        }
        HostMessage::Answer { name, value } if name == "action" && value == CHECK => Action::Check,
        HostMessage::Answer { name, value } if name == "cleanup" && value == CLEAN => Action::Clean,
        _ => return exit(),
    };
    perform(action)
}
