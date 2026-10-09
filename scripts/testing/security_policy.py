"""Assess complete reports; never hide unfixed or lower-severity findings."""
import json


def assess(report):
    if (report.get('SchemaVersion') != 2 or report.get('ArtifactType') != 'container_image'
            or not isinstance(report.get('Results'), list) or not report['Results']
            or not report.get('Metadata', {}).get('ImageID')):
        raise ValueError('Expected a complete Trivy image report with image identity and results')
    vulnerabilities, secrets = [], []
    for result in report['Results']:
        if not isinstance(result, dict) or not result.get('Type'):
            raise ValueError('Malformed Trivy result')
        for key, destination in [('Vulnerabilities', vulnerabilities), ('Secrets', secrets)]:
            findings = result.get(key) or []
            if not isinstance(findings, list) or any(not isinstance(item, dict) for item in findings):
                raise ValueError(f'Malformed Trivy {key}')
            destination.extend(findings)
    for finding in vulnerabilities:
        if (not finding.get('VulnerabilityID') or finding.get('Severity') not in
                ('UNKNOWN', 'LOW', 'MEDIUM', 'HIGH', 'CRITICAL')):
            raise ValueError('Incomplete vulnerability identity or severity')
    blockers = [finding for finding in vulnerabilities if finding['Severity'] in ('HIGH', 'CRITICAL')]
    return {'vulnerability_findings': len(vulnerabilities), 'high_critical': len(blockers),
            'fixable_high_critical': sum(bool(finding.get('FixedVersion')) for finding in blockers),
            'unfixed_high_critical': sum(not finding.get('FixedVersion') for finding in blockers),
            'secret_findings': len(secrets),
            'blocker_ids': sorted({finding['VulnerabilityID'] for finding in blockers}),
            'passed': not blockers and not secrets}


def assess_go(text):
    decoder = json.JSONDecoder()
    messages = []
    while text.strip():
        message, end = decoder.raw_decode(text.lstrip())
        if not isinstance(message, dict) or len(message) != 1:
            raise ValueError('Malformed govulncheck stream message')
        messages.append(message)
        text = text.lstrip()[end:]
    if not messages or 'config' not in messages[0]:
        raise ValueError('govulncheck configuration missing')
    config = messages[0]['config']
    if (config.get('protocol_version') != 'v1.0.0' or config.get('scan_level') != 'symbol'
            or config.get('scan_mode') != 'source' or not config.get('go_version')):
        raise ValueError('Expected source analysis at symbol level with a Go version')
    sboms = [message['SBOM'] for message in messages if 'SBOM' in message]
    if len(sboms) != 1 or not sboms[0].get('roots') or not sboms[0].get('modules'):
        raise ValueError('govulncheck analyzed-package inventory missing')
    osvs = {message['osv']['id'] for message in messages if 'osv' in message}
    findings, reachable = [], set()
    for message in messages:
        if set(message) - {'config', 'progress', 'SBOM', 'osv', 'finding'}:
            raise ValueError('Unrecognized govulncheck message')
        if 'finding' not in message:
            continue
        finding = message['finding']
        if finding.get('osv') not in osvs or not finding.get('trace'):
            raise ValueError('Incomplete govulncheck finding')
        findings.append(finding)
        if finding['trace'][0].get('function'):
            reachable.add(finding['osv'])
    return {'finding_count': len(findings), 'reachable_ids': sorted(reachable),
            'scanner': config, 'passed': not reachable}
