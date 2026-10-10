//! What a freedesktop desktop knows about itself without asking any
//! compositor: which applications are installed, and how to launch one.

use crate::sysvalue::SysValue;
use std::collections::BTreeMap;

/// The `.desktop` files of every applications folder, without the hidden ones.
pub fn applications() -> SysValue {
    let home = std::env::var("HOME").unwrap_or_default();
    let data_dirs = std::env::var("XDG_DATA_DIRS").unwrap_or_else(|_| "/usr/local/share:/usr/share".into());
    let mut folders = vec![
        format!("{home}/.local/share/applications"),
        format!("{home}/.local/share/flatpak/exports/share/applications"),
        "/var/lib/flatpak/exports/share/applications".to_string(),
    ];
    folders.extend(data_dirs.split(':').map(|d| format!("{d}/applications")));
    // By name, and the first folder wins: the user's overrides the system's.
    // Name → (command, icon, the file's id, the X11 class it says it has,
    // its name in the user's language, its categories).
    let mut apps: BTreeMap<String, (String, String, String, String, String, String)> = BTreeMap::new();
    // `es_ES.UTF-8` → `Name[es_ES]`, then `Name[es]`.
    let lang = ["LC_ALL", "LC_MESSAGES", "LANG"].iter().filter_map(|v| std::env::var(v).ok()).find(|v| !v.is_empty()).unwrap_or_default();
    let lang = lang.split(['.', '@']).next().unwrap_or("").to_owned();
    let short = lang.split('_').next().unwrap_or("").to_owned();
    let (key_long, key_short) = (format!("Name[{lang}]"), format!("Name[{short}]"));
    for folder in folders {
        let Ok(dir) = std::fs::read_dir(&folder) else { continue };
        for f in dir.filter_map(Result::ok).filter(|f| f.path().extension().is_some_and(|e| e == "desktop")) {
            let Ok(text) = std::fs::read_to_string(f.path()) else { continue };
            let (mut name, mut command, mut icon, mut hidden, mut inside) = (None, None, String::new(), false, false);
            let mut class = String::new();
            let (mut local_long, mut local_short, mut categories) = (None, None, String::new());
            // `org.gnome.Calculator.desktop` is `org.gnome.Calculator`: the
            // app id its windows say, so a window can be told whose it is.
            let id = f.path().file_stem().and_then(|s| s.to_str()).unwrap_or("").to_owned();
            for l in text.lines() {
                if l.starts_with('[') {
                    inside = l == "[Desktop Entry]";
                } else if inside {
                    match l.split_once('=') {
                        Some(("Name", v)) => name = name.or(Some(v.to_owned())),
                        Some(("Exec", v)) => command = Some(v.split_whitespace().filter(|p| !p.starts_with('%')).collect::<Vec<_>>().join(" ")),
                        Some(("Icon", v)) => icon = v.to_owned(),
                        Some(("StartupWMClass", v)) => class = v.to_owned(),
                        Some(("Categories", v)) => categories = v.to_owned(),
                        Some((k, v)) if !lang.is_empty() && k == key_long => local_long = local_long.or(Some(v.to_owned())),
                        Some((k, v)) if !short.is_empty() && k == key_short => local_short = local_short.or(Some(v.to_owned())),
                        Some(("NoDisplay" | "Hidden", "true")) => hidden = true,
                        Some(("Type", v)) if v != "Application" => hidden = true,
                        _ => {}
                    }
                }
            }
            if let (Some(n), Some(o), false) = (name, command, hidden) {
                let local = local_long.or(local_short).unwrap_or_else(|| n.clone());
                apps.entry(n).or_insert((o, icon, id, class, local, categories));
            }
        }
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
                    // `Name[es]`, as the user's language says it (the name itself if it has none).
                    ("local_name".into(), SysValue::Text(local)),
                    // `Categories=`, as written: `Utility;Calculator;`.
                    ("categories".into(), SysValue::Text(categories)),
                ])
            })
            .collect(),
    )
}

/// Launches a command and forgets about it: it is not a child of the logic, and does not die with us.
///
/// Only what really is an installed application: otherwise, `apps.launch`
/// would be a way to run anything with the permission to "see the apps".
pub fn launch(command: &str) -> Result<(), String> {
    use std::process::{Command, Stdio};
    let SysValue::List(apps) = applications() else { return Err("I don't know what applications there are".into()) };
    let known = apps.iter().any(|a| matches!(a, SysValue::Map(m) if m.iter().any(|(k, v)| k == "exec" && matches!(v, SysValue::Text(o) if o == command))));
    if !known {
        return Err(format!("'{command}' is none of the installed applications: apps.launch only launches what the `apps` service has reported"));
    }
    let mut launch = Command::new("setsid");
    let mut child = launch.args(["-f", "sh", "-c", command]).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn().map_err(|e| e.to_string())?;
    std::thread::spawn(move || {
        let _ = child.wait();
    });
    Ok(())
}

/// Resolves an icon name to an absolute file path on disk if available.
pub fn resolve_icon_path(icon_name: &str) -> Option<String> {
    if icon_name.is_empty() {
        return None;
    }
    let p = std::path::Path::new(icon_name);
    if p.is_absolute() && p.exists() {
        return Some(icon_name.to_string());
    }

    let home = std::env::var("HOME").unwrap_or_default();
    let bases: Vec<String> = vec![
        format!("{home}/.local/share/icons/hicolor/scalable/apps"),
        format!("{home}/.local/share/icons/hicolor/48x48/apps"),
        format!("{home}/.local/share/icons/hicolor/64x64/apps"),
        format!("{home}/.local/share/icons/hicolor/128x128/apps"),
        format!("{home}/.local/share/icons/hicolor/256x256/apps"),
        format!("{home}/.local/share/icons/FairyWren_Dark/apps/48"),
        format!("{home}/.local/share/icons/FairyWren_Dark/apps/scalable"),
        format!("{home}/.local/share/flatpak/exports/share/icons/hicolor/scalable/apps"),
        format!("{home}/.local/share/flatpak/exports/share/icons/hicolor/48x48/apps"),
        format!("{home}/.local/share/flatpak/exports/share/icons/hicolor/128x128/apps"),
        format!("{home}/.local/share/flatpak/exports/share/icons/hicolor/256x256/apps"),
        "/var/lib/flatpak/exports/share/icons/hicolor/scalable/apps".into(),
        "/var/lib/flatpak/exports/share/icons/hicolor/48x48/apps".into(),
        "/var/lib/flatpak/exports/share/icons/hicolor/128x128/apps".into(),
        "/var/lib/flatpak/exports/share/icons/hicolor/256x256/apps".into(),
        "/usr/share/pixmaps".into(),
        "/usr/share/icons/hicolor/scalable/apps".into(),
        "/usr/share/icons/hicolor/48x48/apps".into(),
        "/usr/share/icons/hicolor/64x64/apps".into(),
        "/usr/share/icons/hicolor/128x128/apps".into(),
        "/usr/share/icons/hicolor/256x256/apps".into(),
        "/usr/share/icons/hicolor/512x512/apps".into(),
        "/usr/share/icons/Papirus/48x48/apps".into(),
        "/usr/share/icons/Papirus/scalable/apps".into(),
        "/usr/share/icons/Papirus-Dark/48x48/apps".into(),
        "/usr/share/icons/Papirus-Dark/scalable/apps".into(),
        "/usr/share/icons/breeze/apps/48".into(),
        "/usr/share/icons/breeze/apps/scalable".into(),
        "/usr/share/icons/breeze-dark/apps/48".into(),
        "/usr/share/icons/breeze-dark/apps/scalable".into(),
        "/usr/share/icons/Adwaita/48x48/apps".into(),
        "/usr/share/icons/Adwaita/scalable/apps".into(),
    ];

    // If icon_name already includes an extension
    if icon_name.contains('.') {
        for base in &bases {
            let candidate = format!("{base}/{icon_name}");
            if std::path::Path::new(&candidate).exists() {
                return Some(candidate);
            }
        }
    }

    let extensions = ["svg", "png", "xpm"];
    for base in &bases {
        for ext in &extensions {
            let candidate = format!("{base}/{icon_name}.{ext}");
            if std::path::Path::new(&candidate).exists() {
                return Some(candidate);
            }
        }
    }
    None
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
