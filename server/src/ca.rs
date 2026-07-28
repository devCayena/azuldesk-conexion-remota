use anyhow::Result;
use rcgen::{CertificateParams, KeyPair, KeyUsagePurpose, IsCa, BasicConstraints};

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

    pub fn issue_device_cert(&self, _peer_id: &str, _mac_address: &str) -> Result<String> {
        let ca_key = KeyPair::from_pem(&self.ca_key_pem)?;
        let ca_cert = CertificateParams::from_ca_cert_pem(&self.ca_cert_pem)?
            .self_signed(&ca_key)?;
        let device_key = KeyPair::generate()?;
        let mut params = CertificateParams::new(vec![])?;
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
}
