//! What a freedesktop desktop knows about itself without asking any
//! compositor: which applications are installed, and how to launch one.
//!
//! Powered by spec-compliant `freedesktop-desktop-entry` and `freedesktop-icons`.

use std::collections::BTreeMap;
use freedesktop_desktop_entry::{desktop_entries, get_languages_from_env};

use crate::sysvalue::SysValue;

/// The `.desktop` files of every applications folder, without the hidden ones.
pub fn applications() -> SysValue {
    let languages = get_languages_from_env();
    let entries = desktop_entries(&languages);

    // Map by name to prevent duplicates; highest priority folder wins
    let mut apps: BTreeMap<String, (String, String, String, String, String, String)> = BTreeMap::new();

    for entry in entries {
        // Filter out non-applications and hidden entries
        if entry.type_() != Some("Application") || entry.no_display() || entry.hidden() {
            continue;
        }

        let Some(raw_exec) = entry.exec() else { continue };
        // Strip freedesktop field codes (%u, %U, %f, %F, %i, %c, %k)
        let command = raw_exec
            .split_whitespace()
            .filter(|part| !part.starts_with('%'))
            .collect::<Vec<_>>()
            .join(" ");

        if command.is_empty() {
            continue;
        }

        let name = entry.name(&languages).unwrap_or_default().to_string();
        if name.is_empty() {
            continue;
        }

        let icon = entry.icon().unwrap_or_default().to_string();
        let id = entry.appid.clone();
        let wmclass = entry.startup_wm_class().unwrap_or_default().to_string();
        let categories = entry.categories().map(|c| c.join(";")).unwrap_or_default();
        let local_name = name.clone();

        apps.entry(name).or_insert((command, icon, id, wmclass, local_name, categories));
    }

    SysValue::List(
        apps.into_iter()
            .map(|(n, (o, i, id, class, local, categories))| {
                SysValue::Map(vec![
                    ("name".into(), SysValue::Text(n)),
                    ("exec".into(), SysValue::Text(o)),
                    ("icon".into(), SysValue::Text(i)),
                    ("id".into(), SysValue::Text(id)),
                    ("wmclass".into(), SysValue::Text(class)),
                    ("local_name".into(), SysValue::Text(local)),
                    ("categories".into(), SysValue::Text(categories)),
                ])
            })
            .collect(),
    )
}

/// Launches a command and forgets about it: it is not a child of the logic, and does not die with us.
pub fn launch(command: &str) -> Result<(), String> {
    use std::process::{Command, Stdio};
    let SysValue::List(apps) = applications() else {
        return Err("I don't know what applications there are".into());
    };
    let known = apps.iter().any(|a| {
        matches!(a, SysValue::Map(m) if m.iter().any(|(k, v)| k == "exec" && matches!(v, SysValue::Text(o) if o == command)))
    });
    if !known {
        return Err(format!(
            "'{command}' is none of the installed applications: apps.launch only launches what the `apps` service has reported"
        ));
    }
    let command_str = command.to_string();
    tokio::task::spawn_blocking(move || {
        let mut launch = Command::new("setsid");
        if let Ok(mut child) = launch
            .args(["-f", "sh", "-c", &command_str])
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn()
        {
            let _ = child.wait();
        }
    });
    Ok(())
}

/// Resolves an icon name to an absolute file path on disk if available using freedesktop-icons.
pub fn resolve_icon_path(icon_name: &str) -> Option<String> {
    if icon_name.is_empty() {
        return None;
    }
    let p = std::path::Path::new(icon_name);
    if p.is_absolute() && p.exists() {
        return Some(icon_name.to_string());
    }

    freedesktop_icons::lookup(icon_name)
        .with_size(48)
        .with_cache()
        .find()
        .map(|p| p.to_string_lossy().to_string())
        .or_else(|| {
            // Check common pixmaps fallback
            let pixmaps = format!("/usr/share/pixmaps/{}", icon_name);
            if std::path::Path::new(&pixmaps).exists() {
                Some(pixmaps)
            } else {
                let pixmaps_png = format!("/usr/share/pixmaps/{}.png", icon_name);
                if std::path::Path::new(&pixmaps_png).exists() {
                    Some(pixmaps_png)
                } else {
                    None
                }
            }
        })
}

/// Returns a typed list of installed desktop applications.
pub fn list_apps() -> Vec<beskar_core::models::AppItem> {
    if let SysValue::List(apps) = applications() {
        apps.into_iter()
            .filter_map(|val| {
                if let SysValue::Map(m) = val {
                    let find_str = |k: &str| {
                        m.iter()
                            .find(|(key, _)| key == k)
                            .and_then(|(_, v)| match v {
                                SysValue::Text(t) => Some(t.clone()),
                                _ => None,
                            })
                            .unwrap_or_default()
                    };
                    let raw_icon = find_str("icon");
                    let icon = resolve_icon_path(&raw_icon).unwrap_or(raw_icon);
                    Some(beskar_core::models::AppItem {
                        name: find_str("name"),
                        exec: find_str("exec"),
                        icon,
                        id: find_str("id"),
                        wmclass: find_str("wmclass"),
                        local_name: find_str("local_name"),
                        categories: find_str("categories"),
                    })
                } else {
                    None
                }
            })
            .collect()
    } else {
        Vec::new()
    }
}
