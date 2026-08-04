use crate::packets::{ARTNET_PORT, SACN_PORT, artnet_dmx, artnet_poll, sacn_dmx, sacn_multicast};
use serde::{Deserialize, Serialize};
use serialport::{DataBits, FlowControl, Parity, SerialPort, StopBits};
use socket2::{Domain, Protocol, Socket, Type};
use std::{
    collections::BTreeMap,
    io::{ErrorKind, Write},
    net::{IpAddr, Ipv4Addr, SocketAddr, UdpSocket},
    thread,
    time::{Duration, Instant},
};
use thiserror::Error;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum OutputConfig {
    Preview,
    ArtNet {
        host: String,
        #[serde(default = "default_artnet_port")]
        port: u16,
    },
    Sacn {
        host: Option<String>,
        #[serde(default = "default_sacn_port")]
        port: u16,
        #[serde(default = "default_priority")]
        priority: u8,
    },
    OpenDmx {
        path: String,
    },
}
fn default_artnet_port() -> u16 {
    ARTNET_PORT
}
fn default_sacn_port() -> u16 {
    SACN_PORT
}
fn default_priority() -> u8 {
    100
}

#[derive(Debug, Error)]
pub enum OutputError {
    #[error("network output failed: {0}")]
    Network(#[from] std::io::Error),
    #[error("USB DMX failed: {0}")]
    Serial(#[from] serialport::Error),
    #[error("universe {0} is outside this protocol's range")]
    Universe(u16),
}

pub trait OutputDriver: Send {
    fn send(
        &mut self,
        universe: u16,
        frame: &[u8; 512],
        terminated: bool,
    ) -> Result<(), OutputError>;
    fn label(&self) -> String;
}

pub fn open_output(config: &OutputConfig) -> Result<Box<dyn OutputDriver>, OutputError> {
    Ok(match config {
        OutputConfig::Preview => Box::new(PreviewOutput),
        OutputConfig::ArtNet { host, port } => {
            Box::new(UdpOutput::new(host, *port, UdpKind::ArtNet)?)
        }
        OutputConfig::Sacn {
            host,
            port,
            priority,
        } => Box::new(UdpOutput::new(
            host.as_deref().unwrap_or(""),
            *port,
            UdpKind::Sacn(*priority),
        )?),
        OutputConfig::OpenDmx { path } => Box::new(OpenDmxOutput::new(path)?),
    })
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ArtNetNode {
    pub host: String,
    pub name: String,
    pub short_name: String,
    pub port_count: u16,
}

pub fn discover_artnet(timeout: Duration) -> Result<Vec<ArtNetNode>, OutputError> {
    let raw_socket = Socket::new(Domain::IPV4, Type::DGRAM, Some(Protocol::UDP))?;
    raw_socket.set_reuse_address(true)?;
    #[cfg(unix)]
    raw_socket.set_reuse_port(true)?;
    raw_socket.bind(&SocketAddr::from((Ipv4Addr::UNSPECIFIED, ARTNET_PORT)).into())?;
    let socket: UdpSocket = raw_socket.into();
    socket.set_broadcast(true)?;
    socket.set_read_timeout(Some(Duration::from_millis(120)))?;

    let mut targets = vec![
        Ipv4Addr::BROADCAST,
        Ipv4Addr::new(2, 255, 255, 255),
        Ipv4Addr::new(10, 255, 255, 255),
    ];
    if let Some(local) = local_ipv4() {
        let octets = local.octets();
        targets.push(Ipv4Addr::new(octets[0], octets[1], octets[2], 255));
    }
    targets.sort_unstable();
    targets.dedup();
    let poll = artnet_poll();
    for target in targets {
        let _ = socket.send_to(&poll, (target, ARTNET_PORT));
    }

    let mut deadline = Instant::now() + timeout;
    let mut nodes = BTreeMap::new();
    while Instant::now() < deadline {
        let mut reply = [0_u8; 1024];
        match socket.recv_from(&mut reply) {
            Ok((length, source)) => {
                if let Some(node) = parse_artpoll_reply(&reply[..length], source) {
                    nodes.insert(node.host.clone(), node);
                    deadline = deadline.min(Instant::now() + Duration::from_millis(150));
                }
            }
            Err(error) if matches!(error.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) => {}
            Err(error) => return Err(OutputError::Network(error)),
        }
    }
    Ok(nodes.into_values().collect())
}

fn local_ipv4() -> Option<Ipv4Addr> {
    let socket = UdpSocket::bind((Ipv4Addr::UNSPECIFIED, 0)).ok()?;
    socket.connect((Ipv4Addr::new(8, 8, 8, 8), 80)).ok()?;
    match socket.local_addr().ok()?.ip() {
        IpAddr::V4(ip) if !ip.is_loopback() => Some(ip),
        _ => None,
    }
}

fn parse_artpoll_reply(packet: &[u8], source: SocketAddr) -> Option<ArtNetNode> {
    if packet.len() < 174
        || &packet[..8] != b"Art-Net\0"
        || u16::from_le_bytes([packet[8], packet[9]]) != 0x2100
    {
        return None;
    }
    let host = match source.ip() {
        IpAddr::V4(ip) => ip.to_string(),
        IpAddr::V6(_) => Ipv4Addr::new(packet[10], packet[11], packet[12], packet[13]).to_string(),
    };
    let short_name = artnet_string(&packet[26..44]);
    let name = artnet_string(&packet[44..108]);
    Some(ArtNetNode {
        host,
        name: if name.is_empty() {
            short_name.clone()
        } else {
            name
        },
        short_name,
        port_count: u16::from_be_bytes([packet[172], packet[173]]),
    })
}

fn artnet_string(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes)
        .trim_end_matches(char::from(0))
        .trim()
        .to_owned()
}

struct PreviewOutput;
impl OutputDriver for PreviewOutput {
    fn send(&mut self, _: u16, _: &[u8; 512], _: bool) -> Result<(), OutputError> {
        Ok(())
    }
    fn label(&self) -> String {
        "Preview only".to_owned()
    }
}

enum UdpKind {
    ArtNet,
    Sacn(u8),
}
struct UdpOutput {
    socket: UdpSocket,
    host: String,
    port: u16,
    kind: UdpKind,
    sequence: u8,
}
impl UdpOutput {
    fn new(host: &str, port: u16, kind: UdpKind) -> Result<Self, OutputError> {
        let socket = UdpSocket::bind("0.0.0.0:0")?;
        socket.set_broadcast(true)?;
        Ok(Self {
            socket,
            host: host.to_owned(),
            port,
            kind,
            sequence: 1,
        })
    }
}
impl OutputDriver for UdpOutput {
    fn send(
        &mut self,
        universe: u16,
        frame: &[u8; 512],
        terminated: bool,
    ) -> Result<(), OutputError> {
        self.sequence = self.sequence.wrapping_add(1).max(1);
        let (host, packet) = match self.kind {
            UdpKind::ArtNet if universe > 0 && universe <= 32_768 => (
                self.host.clone(),
                artnet_dmx(universe - 1, self.sequence, frame),
            ),
            UdpKind::ArtNet => return Err(OutputError::Universe(universe)),
            UdpKind::Sacn(priority) if universe > 0 && universe <= 63999 => (
                if self.host.is_empty() {
                    sacn_multicast(universe)
                } else {
                    self.host.clone()
                },
                sacn_dmx(universe, priority, self.sequence, frame, terminated),
            ),
            UdpKind::Sacn(_) => return Err(OutputError::Universe(universe)),
        };
        self.socket.send_to(&packet, (host.as_str(), self.port))?;
        Ok(())
    }
    fn label(&self) -> String {
        match self.kind {
            UdpKind::ArtNet => format!("Art-Net · {}", self.host),
            UdpKind::Sacn(_) => {
                if self.host.is_empty() {
                    "sACN · multicast".to_owned()
                } else {
                    format!("sACN · {}", self.host)
                }
            }
        }
    }
}

struct OpenDmxOutput {
    port: Box<dyn SerialPort>,
}
impl OpenDmxOutput {
    fn new(path: &str) -> Result<Self, OutputError> {
        let port = serialport::new(path, 250_000)
            .data_bits(DataBits::Eight)
            .parity(Parity::None)
            .stop_bits(StopBits::Two)
            .flow_control(FlowControl::None)
            .timeout(Duration::from_millis(30))
            .open()?;
        Ok(Self { port })
    }
}
impl OutputDriver for OpenDmxOutput {
    fn send(&mut self, universe: u16, frame: &[u8; 512], _: bool) -> Result<(), OutputError> {
        if universe != 1 {
            return Err(OutputError::Universe(universe));
        }
        self.port.set_break()?;
        thread::sleep(Duration::from_micros(120));
        self.port.clear_break()?;
        thread::sleep(Duration::from_micros(12));
        self.port.write_all(&[0])?;
        self.port.write_all(frame)?;
        self.port.flush()?;
        Ok(())
    }
    fn label(&self) -> String {
        format!(
            "USB DMX · {}",
            self.port.name().unwrap_or_else(|| "FTDI".to_owned())
        )
    }
}

pub fn serial_outputs() -> Vec<SerialOutput> {
    serialport::available_ports()
        .unwrap_or_default()
        .into_iter()
        .map(|port| {
            let (vid, pid, manufacturer, product) = match port.port_type {
                serialport::SerialPortType::UsbPort(info) => (
                    Some(info.vid),
                    Some(info.pid),
                    info.manufacturer,
                    info.product,
                ),
                _ => (None, None, None, None),
            };
            SerialOutput {
                path: port.port_name,
                vid,
                pid,
                manufacturer,
                product,
            }
        })
        .collect()
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SerialOutput {
    pub path: String,
    pub vid: Option<u16>,
    pub pid: Option<u16>,
    pub manufacturer: Option<String>,
    pub product: Option<String>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_artpoll_reply_identity() {
        let mut packet = [0_u8; 174];
        packet[..8].copy_from_slice(b"Art-Net\0");
        packet[8..10].copy_from_slice(&0x2100_u16.to_le_bytes());
        packet[26..35].copy_from_slice(b"eDMX1 P\0\0");
        packet[44..60].copy_from_slice(b"THE END - eDMX1\0");
        packet[172..174].copy_from_slice(&1_u16.to_be_bytes());
        let source = "10.0.0.140:6454".parse().unwrap();
        let node = parse_artpoll_reply(&packet, source).unwrap();
        assert_eq!(node.host, "10.0.0.140");
        assert_eq!(node.short_name, "eDMX1 P");
        assert_eq!(node.port_count, 1);
    }
}
