use std::path::Path;
use beskar_core::models::AppItem;
use gpui_kit::assets::IconName;
use crate::modules::power_menu::PowerAction;
use super::calc::{evaluate_math, format_calc_result};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LauncherCategory {
    All,
    Apps,
    Settings,
    Calc,
    Power,
}

impl LauncherCategory {
    pub const ALL: [Self; 5] = [
        Self::All,
        Self::Apps,
        Self::Settings,
        Self::Calc,
        Self::Power,
    ];

    pub fn label(&self) -> &'static str {
        match self {
            Self::All => "All",
            Self::Apps => "Apps",
            Self::Settings => "Settings",
            Self::Calc => "Calculator",
            Self::Power => "Power",
        }
    }

    pub fn icon(&self) -> IconName {
        match self {
            Self::All => IconName::LayoutGrid,
            Self::Apps => IconName::Rocket,
            Self::Settings => IconName::Settings,
            Self::Calc => IconName::Calculator,
            Self::Power => IconName::Power,
        }
    }
}

#[derive(Debug, Clone)]
pub struct SettingItem {
    pub id: &'static str,
    pub title: &'static str,
    pub description: &'static str,
    pub icon: IconName,
    pub keywords: &'static [&'static str],
}

pub const SETTINGS_ITEMS: &[SettingItem] = &[
    SettingItem {
        id: "keybinds",
        title: "Keybinds & Shortcuts",
        description: "Configure window management and shell keybindings",
        icon: IconName::Keyboard,
        keywords: &["keybind", "hotkey", "shortcut", "bind", "keyboard"],
    },
    SettingItem {
        id: "appearance",
        title: "Appearance & Themes",
        description: "Customize wallpaper, dynamic HSL colors, and blur shaders",
        icon: IconName::Palette,
        keywords: &["theme", "appearance", "color", "dark", "light", "wallpaper", "blur"],
    },
    SettingItem {
        id: "audio",
        title: "Sound & Audio Hardware",
        description: "Configure PipeWire sinks, volume, and cava visualizer",
        icon: IconName::Volume2,
        keywords: &["audio", "sound", "volume", "sink", "speaker", "pipewire"],
    },
    SettingItem {
        id: "network",
        title: "Network & Bluetooth",
        description: "Manage Wi-Fi connections, VPNs, and paired Bluetooth devices",
        icon: IconName::Wifi,
        keywords: &["wifi", "network", "bluetooth", "internet", "ethernet"],
    },
    SettingItem {
        id: "displays",
        title: "Displays & Dynamic Notch",
        description: "Resolution, fractional scaling, and convex island geometry",
        icon: IconName::Monitor,
        keywords: &["display", "monitor", "screen", "notch", "convex", "scale"],
    },
    SettingItem {
        id: "extensions",
        title: "Packages & Extensions",
        description: "Manage shell plugins, custom cards, and community widgets",
        icon: IconName::Package,
        keywords: &["package", "extension", "plugin", "widget", "store"],
    },
];

#[derive(Debug, Clone)]
pub enum LauncherResult {
    Calculation {
        expr: String,
        result: f64,
        formatted: String,
    },
    App(AppItem),
    Setting(SettingItem),
    Power(PowerAction),
}

impl LauncherResult {
    pub fn title(&self) -> String {
        match self {
            Self::Calculation { formatted, .. } => format!("= {}", formatted),
            Self::App(app) => app.name.clone(),
            Self::Setting(setting) => setting.title.to_string(),
            Self::Power(action) => action.label().to_string(),
        }
    }

    pub fn subtitle(&self) -> String {
        match self {
            Self::Calculation { expr, .. } => format!("Calculation result for '{}' • Press Enter to copy", expr),
            Self::App(app) => {
                if !app.exec.is_empty() {
                    app.exec.clone()
                } else if !app.categories.is_empty() {
                    app.categories.clone()
                } else {
                    "Application".to_string()
                }
            }
            Self::Setting(setting) => setting.description.to_string(),
            Self::Power(action) => match action {
                PowerAction::Lock => "Lock current user session".to_string(),
                PowerAction::Suspend => "Suspend system to RAM".to_string(),
                PowerAction::Logout => "Terminate current user session".to_string(),
                PowerAction::Restart => "Reboot the operating system".to_string(),
                PowerAction::Shutdown => "Power off the computer".to_string(),
            },
        }
    }

    pub fn category(&self) -> LauncherCategory {
        match self {
            Self::Calculation { .. } => LauncherCategory::Calc,
            Self::App(_) => LauncherCategory::Apps,
            Self::Setting(_) => LauncherCategory::Settings,
            Self::Power(_) => LauncherCategory::Power,
        }
    }

    pub fn icon(&self) -> IconName {
        match self {
            Self::Calculation { .. } => IconName::Calculator,
            Self::App(_) => IconName::Rocket,
            Self::Setting(setting) => setting.icon,
            Self::Power(action) => action.icon(),
        }
    }

    pub fn icon_path(&self) -> Option<&str> {
        match self {
            Self::App(app) if !app.icon.is_empty() && Path::new(&app.icon).exists() => {
                Some(&app.icon)
            }
            _ => None,
        }
    }
}

pub fn search_unified(
    apps: &[AppItem],
    query: &str,
    category: LauncherCategory,
) -> Vec<LauncherResult> {
    let q = query.trim().to_lowercase();
    let mut results: Vec<LauncherResult> = Vec::new();

    // 1. Math / Calculator Dispatcher
    if (category == LauncherCategory::All || category == LauncherCategory::Calc) && !q.is_empty() {
        if let Some(val) = evaluate_math(&q) {
            results.push(LauncherResult::Calculation {
                expr: query.trim().to_string(),
                result: val,
                formatted: format_calc_result(val),
            });
        }
    }

    // 2. Power Commands Dispatcher
    if category == LauncherCategory::All || category == LauncherCategory::Power {
        let power_matches = [
            (PowerAction::Shutdown, &["shutdown", "power off", "poweroff", "turn off"][..]),
            (PowerAction::Restart, &["reboot", "restart", "reset"][..]),
            (PowerAction::Lock, &["lock", "lockscreen"][..]),
            (PowerAction::Logout, &["logout", "log off", "sign out", "exit"][..]),
            (PowerAction::Suspend, &["suspend", "sleep", "hibernate"][..]),
        ];

        for (action, keywords) in power_matches {
            let matched = if q.is_empty() {
                category == LauncherCategory::Power
            } else {
                keywords.iter().any(|k| k.starts_with(&q) || q.starts_with(k))
            };

            if matched {
                results.push(LauncherResult::Power(action));
            }
        }
    }

    // 3. Settings Search Dispatcher
    if category == LauncherCategory::All || category == LauncherCategory::Settings {
        for setting in SETTINGS_ITEMS {
            let matched = if q.is_empty() {
                category == LauncherCategory::Settings
            } else {
                setting.title.to_lowercase().contains(&q)
                    || setting.keywords.iter().any(|k| k.contains(&q))
            };

            if matched {
                results.push(LauncherResult::Setting(setting.clone()));
            }
        }
    }

    // 4. Desktop Applications Search Dispatcher
    if category == LauncherCategory::All || category == LauncherCategory::Apps {
        struct ScoredApp {
            app: AppItem,
            score: u32,
        }

        let mut scored_apps: Vec<ScoredApp> = Vec::new();
        for app in apps {
            if q.is_empty() {
                scored_apps.push(ScoredApp {
                    app: app.clone(),
                    score: 100,
                });
                continue;
            }

            let name_lower = app.name.to_lowercase();
            let local_lower = app.local_name.to_lowercase();
            let cat_lower = app.categories.to_lowercase();
            let exec_lower = app.exec.to_lowercase();

            let score = if name_lower.starts_with(&q) {
                10
            } else if local_lower.starts_with(&q) {
                20
            } else if name_lower.split_whitespace().any(|w| w.starts_with(&q)) {
                30
            } else if name_lower.contains(&q) {
                40
            } else if local_lower.contains(&q) {
                50
            } else if cat_lower.contains(&q) {
                60
            } else if exec_lower.contains(&q) {
                70
            } else {
                continue;
            };

            scored_apps.push(ScoredApp {
                app: app.clone(),
                score,
            });
        }

        scored_apps.sort_by(|a, b| {
            a.score
                .cmp(&b.score)
                .then_with(|| a.app.name.to_lowercase().cmp(&b.app.name.to_lowercase()))
        });

        for item in scored_apps {
            results.push(LauncherResult::App(item.app));
        }
    }

    results
}
