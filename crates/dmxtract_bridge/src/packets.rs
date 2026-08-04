use uuid::Uuid;

pub const ARTNET_PORT: u16 = 6454;
pub const SACN_PORT: u16 = 5568;

pub fn artnet_poll() -> [u8; 14] {
    let mut packet = [0_u8; 14];
    packet[..8].copy_from_slice(b"Art-Net\0");
    packet[8..10].copy_from_slice(&0x2000_u16.to_le_bytes());
    packet[10..12].copy_from_slice(&14_u16.to_be_bytes());
    packet[12] = 0x02;
    packet[13] = 0;
    packet
}

pub fn artnet_dmx(universe: u16, sequence: u8, dmx: &[u8; 512]) -> Vec<u8> {
    let mut packet = vec![0_u8; 18 + 512];
    packet[..8].copy_from_slice(b"Art-Net\0");
    packet[8..10].copy_from_slice(&0x5000_u16.to_le_bytes());
    packet[10..12].copy_from_slice(&14_u16.to_be_bytes());
    packet[12] = sequence;
    packet[13] = 0;
    packet[14..16].copy_from_slice(&universe.to_le_bytes());
    packet[16..18].copy_from_slice(&512_u16.to_be_bytes());
    packet[18..].copy_from_slice(dmx);
    packet
}

pub fn sacn_dmx(
    universe: u16,
    priority: u8,
    sequence: u8,
    dmx: &[u8; 512],
    terminated: bool,
) -> Vec<u8> {
    const SIZE: usize = 638;
    let mut packet = vec![0_u8; SIZE];
    let mut offset = 0;
    put_u16(&mut packet, &mut offset, 0x0010);
    put_u16(&mut packet, &mut offset, 0);
    packet[offset..offset + 12].copy_from_slice(b"ASC-E1.17\0\0\0");
    offset += 12;
    let root_length = 0x7000 | ((SIZE - offset) as u16 & 0x0fff);
    put_u16(&mut packet, &mut offset, root_length);
    put_u32(&mut packet, &mut offset, 0x00000004);
    let cid = Uuid::new_v5(&Uuid::NAMESPACE_URL, b"https://dmxtract.sho.run/bridge");
    packet[offset..offset + 16].copy_from_slice(cid.as_bytes());
    offset += 16;
    let framing_length = 0x7000 | ((SIZE - offset) as u16 & 0x0fff);
    put_u16(&mut packet, &mut offset, framing_length);
    put_u32(&mut packet, &mut offset, 0x00000002);
    let name = b"DMXtract";
    packet[offset..offset + name.len()].copy_from_slice(name);
    offset += 64;
    packet[offset] = priority.min(200);
    offset += 1;
    put_u16(&mut packet, &mut offset, 0);
    packet[offset] = sequence;
    offset += 1;
    packet[offset] = if terminated { 0x40 } else { 0 };
    offset += 1;
    put_u16(&mut packet, &mut offset, universe);
    let dmp_length = 0x7000 | ((SIZE - offset) as u16 & 0x0fff);
    put_u16(&mut packet, &mut offset, dmp_length);
    packet[offset] = 0x02;
    offset += 1;
    packet[offset] = 0xa1;
    offset += 1;
    put_u16(&mut packet, &mut offset, 0);
    put_u16(&mut packet, &mut offset, 1);
    put_u16(&mut packet, &mut offset, 513);
    packet[offset] = 0;
    offset += 1;
    packet[offset..offset + 512].copy_from_slice(dmx);
    packet
}

pub fn sacn_multicast(universe: u16) -> String {
    format!("239.255.{}.{}", universe >> 8, universe & 0xff)
}

fn put_u16(packet: &mut [u8], offset: &mut usize, value: u16) {
    packet[*offset..*offset + 2].copy_from_slice(&value.to_be_bytes());
    *offset += 2;
}
fn put_u32(packet: &mut [u8], offset: &mut usize, value: u32) {
    packet[*offset..*offset + 4].copy_from_slice(&value.to_be_bytes());
    *offset += 4;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn artnet_packet_has_expected_wire_fields() {
        let packet = artnet_dmx(0x1234, 7, &[0; 512]);
        assert_eq!(&packet[..8], b"Art-Net\0");
        assert_eq!(&packet[8..10], &[0x00, 0x50]);
        assert_eq!(&packet[14..16], &[0x34, 0x12]);
        assert_eq!(&packet[16..18], &[0x02, 0x00]);
    }

    #[test]
    fn artnet_poll_has_expected_wire_fields() {
        let packet = artnet_poll();
        assert_eq!(&packet[..8], b"Art-Net\0");
        assert_eq!(&packet[8..10], &[0x00, 0x20]);
        assert_eq!(&packet[10..12], &[0x00, 0x0e]);
    }

    #[test]
    fn sacn_packet_has_start_code_and_payload() {
        let mut dmx = [0; 512];
        dmx[0] = 42;
        let packet = sacn_dmx(1, 100, 9, &dmx, false);
        assert_eq!(packet.len(), 638);
        assert_eq!(&packet[4..16], b"ASC-E1.17\0\0\0");
        assert_eq!(packet[125], 0);
        assert_eq!(packet[126], 42);
    }
}
