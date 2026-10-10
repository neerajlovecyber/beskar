/// Generic system value representation directly ported from pleamar (`src/platform/mod.rs`).
#[derive(Clone, Debug, PartialEq)]
pub enum SysValue {
    Null,
    Bool(bool),
    Num(f64),
    Text(String),
    List(Vec<SysValue>),
    Map(Vec<(String, SysValue)>),
}
