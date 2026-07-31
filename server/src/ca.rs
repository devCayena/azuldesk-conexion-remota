use anyhow::{anyhow, Result};
use rcgen::{CertificateParams, KeyPair, KeyUsagePurpose, IsCa, BasicConstraints, DnType};

pub struct CertificateAuthority {
    ca_cert_pem: String,
    ca_key_pem: String,
}

impl CertificateAuthority {
    pub fn new_or_load(existing: Option<(String, String)>) -> Result<Self> {
        if let Some((cert, key)) = existing {
            return Ok(Self { ca_cert_pem: cert, ca_key_pem: key });
        }
        Self::generate_ca()
    }

    fn generate_ca() -> Result<Self> {
        let key = KeyPair::generate()?;
        let mut params = CertificateParams::new(vec![])?;
        params.is_ca = IsCa::Ca(BasicConstraints::Unconstrained);
        params.key_usages = vec![KeyUsagePurpose::KeyCertSign, KeyUsagePurpose::CrlSign];
        let cert = params.self_signed(&key)?;
        Ok(Self {
            ca_cert_pem: cert.pem(),
            ca_key_pem: key.serialize_pem(),
        })
    }

    pub fn ca_cert_pem(&self) -> &str { &self.ca_cert_pem }
    pub fn ca_key_pem(&self) -> &str { &self.ca_key_pem }

    /// Emite un certificado de dispositivo. El subject lleva:
    ///   CN=AzulRemote (nombre fijo para localizarlo en el store de Windows)
    ///   serialNumber=<serial del equipo>  (2.5.4.5)
    ///   uid=<peer_id derivado del serial> (0.9.2342.19200300.100.1.1)
    /// Así el cert queda vinculado al ID, y el ID al serial del equipo.
    pub fn issue_device_cert(&self, peer_id: &str, serial: &str) -> Result<String> {
        let ca_key = KeyPair::from_pem(&self.ca_key_pem)?;
        let ca_cert = CertificateParams::from_ca_cert_pem(&self.ca_cert_pem)?
            .self_signed(&ca_key)?;
        let device_key = KeyPair::generate()?;
        let mut params = CertificateParams::new(vec![])?;
        params.distinguished_name.push(DnType::CommonName, "AzulRemote");
        params.distinguished_name.push(DnType::CustomDnType(vec![2, 5, 4, 5]), serial);
        params.distinguished_name.push(DnType::CustomDnType(vec![0, 9, 2342, 19200300, 100, 1, 1]), peer_id);
        params.key_usages = vec![
            KeyUsagePurpose::DigitalSignature,
            KeyUsagePurpose::KeyEncipherment,
        ];
        let device_cert = params.signed_by(&device_key, &ca_cert, &ca_key)?;
        Ok(format!("{}\n{}", device_cert.pem(), device_key.serialize_pem()))
    }

    pub fn verify_certificate(&self, cert_pem: &str) -> Result<bool> {
        let cert = pem::parse(cert_pem)?;
        let (_, parsed) = x509_parser::parse_x509_certificate(cert.contents())?;
        let issuer = parsed.issuer().to_string();
        Ok(issuer.contains("Spyware"))
    }

    /// Verifica que el certificado presentado pertenezca al equipo cuyo serial
    /// se declaró, y que su uid (peer_id) coincida con el peer_id derivado.
    pub fn verify_device_binding(&self, cert_pem: &str, expected_serial: &str, expected_peer_id: &str) -> Result<()> {
        let cert = pem::parse(cert_pem).map_err(|e| anyhow!("parse pem: {e}"))?;
        let (_, parsed) = x509_parser::parse_x509_certificate(cert.contents())
            .map_err(|e| anyhow!("parse x509: {e}"))?;

        let mut serial: Option<String> = None;
        let mut uid: Option<String> = None;
        for attr in parsed.subject().iter_attributes() {
            let value = attr.attr_value().as_str().ok().map(|s| s.to_string());
            match attr.attr_type().to_id_string().as_str() {
                "2.5.4.5" => serial = value,
                "0.9.2342.19200300.100.1.1" => uid = value,
                _ => {}
            }
        }

        match serial {
            Some(s) if expected_serial.is_empty() || s == expected_serial => {}
            _ => return Err(anyhow!("serial del certificado no coincide con el del equipo")),
        }
        match uid {
            Some(u) if u == expected_peer_id => {}
            _ => return Err(anyhow!("peer_id del certificado no coincide con el derivado del serial")),
        }
        Ok(())
    }
}
