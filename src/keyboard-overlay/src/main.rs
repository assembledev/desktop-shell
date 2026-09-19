//! Read-only Rynk session. stdout is newline-delimited state; no key capture.
use anyhow::{Context, Result, bail};
use rynk::rmk_types::{
    action::{Action, KeyAction},
    morse::{HOLD, TAP},
};
use rynk::{Client, RynkDevice, TopicEvent};
use rynk_ble::BleDevice;
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    io::{self, Write},
    time::Duration,
};

fn emit(value: Value) {
    println!("{value}");
    let _ = io::stdout().flush();
}
async fn bounded<T>(
    f: impl std::future::Future<Output = Result<T, rynk::RynkHostError>>,
) -> Result<T> {
    Ok(tokio::time::timeout(Duration::from_secs(8), f)
        .await
        .context("Keyboard did not respond")??)
}
fn words(value: &str) -> String {
    let mut result = String::new();
    for (i, ch) in value.chars().enumerate() {
        if i > 0 && ch.is_uppercase() && value.as_bytes()[i - 1].is_ascii_lowercase() {
            result.push(' ');
        }
        result.push(ch);
    }
    result
}
fn hid(value: &str) -> String {
    match value {
        "PrintScreen" => "PrtSc",
        "PageUp" => "PgUp",
        "PageDown" => "PgDn",
        "Delete" => "Del",
        "Space" => "Space",
        "Enter" => "Enter",
        "Escape" => "Esc",
        "Backspace" => "Bksp",
        "LShift" | "LeftShift" => "Shift",
        "RShift" | "RightShift" => "R Shift",
        "LCtrl" | "LeftControl" => "Ctrl",
        "RCtrl" | "RightControl" => "R Ctrl",
        "LAlt" | "LeftAlt" => "Alt",
        "RAlt" | "RightAlt" => "R Alt",
        "LGui" | "LeftGui" => "Super",
        "RGui" | "RightGui" => "R Super",
        "Left" => "←",
        "Right" => "→",
        "Up" => "↑",
        "Down" => "↓",
        "Tab" => "Tab",
        "Minus" => "−",
        "Equal" => "=",
        "LeftBracket" => "[",
        "RightBracket" => "]",
        "Backslash" => "\\",
        "Semicolon" => ";",
        "Quote" => "'",
        "Grave" => "`",
        "Comma" => ",",
        "Dot" => ".",
        "Slash" => "/",
        _ => return value.strip_prefix("Kc").unwrap_or(value).to_owned(),
    }
    .into()
}
fn action(a: Action, names: &[String]) -> String {
    use rynk::rmk_types::keycode::KeyCode;
    let layer = |n: u8| {
        names
            .get(n as usize)
            .cloned()
            .unwrap_or(format!("Layer {n}"))
    };
    match a {
        Action::No => "—".into(),
        Action::Key(KeyCode::Hid(k)) => hid(&format!("{k:?}")),
        Action::Key(k) => words(
            &format!("{k:?}")
                .replace("Consumer(", "")
                .replace("SystemControl(", "")
                .trim_end_matches(')'),
        ),
        Action::LayerOn(n) => layer(n),
        Action::LayerToggle(n) => format!("Toggle {}", layer(n)),
        Action::LayerToggleOnly(n)
        | Action::DefaultLayer(n)
        | Action::PersistentDefaultLayer(n) => format!("To {}", layer(n)),
        Action::TriggerMacro(n) => format!("Macro {}", n + 1),
        Action::KeyWithModifier(k, m) => {
            format!("{}+{}", modifiers(m.into_bits()), hid(&format!("{k:?}")))
        }
        Action::Modifier(m) => modifiers(m.into_bits()),
        Action::User(n) => match n {
            0..=3 => format!("BT {}", n + 1),
            10 => "Clear BT".into(),
            11 => "Clear all BT".into(),
            12 => "R Boot".into(),
            _ => format!("User {n}"),
        },
        Action::Light(l) => match format!("{l:?}").as_str() {
            "RgbTog" => "RGB on/off".into(),
            "RgbModeForward" => "Effect +".into(),
            "RgbModeReverse" => "Effect −".into(),
            "RgbHui" => "Hue +".into(),
            "RgbHud" => "Hue −".into(),
            "RgbSai" => "Sat +".into(),
            "RgbSad" => "Sat −".into(),
            "RgbVai" => "Bright +".into(),
            "RgbVad" => "Bright −".into(),
            "RgbSpi" => "Speed +".into(),
            "RgbSpd" => "Speed −".into(),
            other => words(other),
        },
        Action::KeyboardControl(k) => words(&format!("{k:?}")),
        _ => words(&format!("{a:?}")),
    }
}
fn modifiers(bits: u8) -> String {
    [
        "Ctrl", "Shift", "Alt", "Super", "R Ctrl", "R Shift", "R Alt", "R Super",
    ]
    .iter()
    .enumerate()
    .filter(|(i, _)| bits & (1 << i) != 0)
    .map(|(_, s)| *s)
    .collect::<Vec<_>>()
    .join("+")
}
fn resolve(keys: &[KeyAction], size: usize, index: usize, active: &[usize]) -> (KeyAction, usize) {
    for &layer in active.iter().rev() {
        let key = keys
            .get(layer * size + index)
            .copied()
            .unwrap_or(KeyAction::No);
        if key != KeyAction::Transparent {
            return (key, layer);
        }
    }
    (KeyAction::No, 0)
}
async fn watch(client: &Client) -> Result<()> {
    let caps = bounded(client.get_capabilities()).await?;
    let info = bounded(client.get_device_info()).await?;
    if caps.num_rows != 6
        || caps.num_cols != 14
        || !info.product_name.to_lowercase().contains("glove80")
    {
        bail!("Connected Rynk device is not a Glove80");
    }
    let layout = bounded(client.get_layout()).await?;
    let variant = layout
        .variants
        .get(layout.default_variant as usize)
        .context("No physical keyboard geometry")?;
    if variant.keys.len() != 80 {
        bail!("Unexpected Glove80 geometry");
    }
    let keys = bounded(client.read_all_keymap()).await?;
    let mut names = Vec::new();
    for n in 0..caps.num_layers {
        let metadata = bounded(client.get_layer_metadata(n)).await?;
        names.push(if metadata.name.is_empty() {
            format!("Layer {n}")
        } else {
            metadata.name.to_string()
        });
    }
    let mut morses = BTreeMap::new();
    for key in &keys {
        if let KeyAction::Morse(n) = key {
            if !morses.contains_key(n) {
                morses.insert(*n, bounded(client.get_morse(*n)).await?);
            }
        }
    }
    loop {
        let state = bounded(client.get_layer_state()).await?;
        let active: Vec<usize> = (0..caps.num_layers as usize)
            .filter(|n| state.is_active(*n as u8))
            .collect();
        let top = active
            .last()
            .copied()
            .unwrap_or(state.default_layer as usize);
        let cells: Vec<Value> = variant.keys.iter().map(|k| {
            let (key, source) = resolve(&keys,84,k.row as usize*14+k.col as usize,&active);
            let (label,detail) = match key {
                KeyAction::No | KeyAction::Transparent => ("—".into(),String::new()),
                KeyAction::Single(a) | KeyAction::Tap(a) => (action(a,&names),String::new()),
                KeyAction::Morse(n) => morses.get(&n).map(|m| (
                    m.actions.get(&TAP).map(|a|action(*a,&names)).unwrap_or("—".into()),
                    m.actions.get(&HOLD).map(|a|format!("hold {}",action(*a,&names))).unwrap_or_default()
                )).unwrap_or((format!("Tap/hold {n}"),String::new())),
                KeyAction::TapHold(t,h,_) => (action(t,&names),format!("hold {}",action(h,&names))),
                _ => (format!("{key:?}"),String::new()),
            };
            json!({"x":k.rect.x,"y":k.rect.y,"w":k.rect.w,"h":k.rect.h,"rotation":k.r,
                "label":label,"detail":detail,"inherited":source!=top,"disabled":key==KeyAction::No})
        }).collect();
        emit(
            json!({"status":"connected","layer":names[top],"layers":active.iter().map(|n|&names[*n]).collect::<Vec<_>>(),"keys":cells}),
        );
        // No polling: consume firmware events, fetch an authoritative snapshot on layer changes.
        loop {
            match client.next_topic().await {
                TopicEvent::LayerChange(_) => break,
                TopicEvent::SleepState(true) => emit(json!({"status":"sleeping"})),
                TopicEvent::SleepState(false) => break,
                _ => {}
            }
        }
    }
}
async fn session() -> Result<()> {
    let mut devices = bounded(BleDevice::discover()).await?;
    if devices.is_empty() {
        bail!("Connect your Glove80 over Bluetooth");
    }
    if devices.len() != 1 {
        bail!("Multiple Rynk keyboards connected; leave one connected");
    }
    let (client, mut driver) = bounded(devices.remove(0).connect()).await?;
    tokio::select! {
        error = driver.run(&client) => bail!("Keyboard disconnected: {error}"),
        result = watch(&client) => result,
    }
}
#[tokio::main(worker_threads = 2)]
async fn main() {
    let run = async {
        let mut delay = 2;
        loop {
            emit(json!({"status":"connecting"}));
            if let Err(e) = session().await {
                emit(json!({"status":"disconnected","message":e.to_string()}));
            }
            tokio::time::sleep(Duration::from_secs(delay)).await;
            delay = (delay * 2).min(30);
        }
    };
    let mut terminate =
        tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()).unwrap();
    tokio::select! { _ = run => {}, _ = terminate.recv() => {}, _ = tokio::signal::ctrl_c() => {} }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn transparent_falls_through_but_disabled_does_not() {
        let base = KeyAction::Single(Action::LayerOn(2));
        assert_eq!(
            resolve(&[base, KeyAction::Transparent], 1, 0, &[0, 1]),
            (base, 0)
        );
        assert_eq!(
            resolve(&[base, KeyAction::No], 1, 0, &[0, 1]),
            (KeyAction::No, 1)
        );
    }
}
