"""Render documentation addresses as reserved test addresses, without changing policy."""


def render_sample(text):
    result = (text.replace('YOUR.IPV4.IP.ADDRESS', '192.0.2.10')
              .replace('YOUR:IPV6:IP:ADDRESS::', '2001:db8::10')
              .replace('VPS.DNS.IP.ADDRESS', '192.0.2.53'))
    for number in range(1, 5):
        result = result.replace(f'VPS:DNS:IP:ADDRESS::{number}', f'2001:db8::{number + 52}')
    return result
