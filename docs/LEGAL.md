# ⚖️ Legal & Compliance Guide - Tor Relay Operators

Country-specific legal considerations, liability notes, and best practices for operating a Tor relay.

---

## Table of Contents

- [Global Overview](#global-overview)
- [Legal Frameworks](#legal-frameworks)
- [By Country/Region](#by-countryregion)
- [Relay Type Differences](#relay-type-differences)
- [Liability & Protection](#liability--protection)
- [Best Practices](#best-practices)
- [Abuse Handling](#abuse-handling)
- [Legal Resources](#legal-resources)

---

## ⚠️ DISCLAIMER

**This guide is informational only and does not constitute legal advice.** Laws vary by country, jurisdiction, and change frequently. Operating a Tor relay may carry legal risks depending on your location and political context. Consult a local attorney if you have concerns about your specific situation.

---

## Global Overview

### Why This Guide?

Tor relay operation is generally legal, but specific laws vary:

- 🟢 **Safe in most democracies** - USA, EU, Canada, Australia explicitly protect relay operation
- 🟡 **Gray area in some countries** - Context and purpose matter; legal status uncertain
- 🔴 **Risky in authoritarian regimes** - May be criminalized or heavily restricted

### General Principles

**Core truths:**

1. **Relay operators don't control traffic content** - Tor automatically routes through multiple relays
2. **Guard relays are safest** - Never see onion addresses or hidden service traffic
3. **Exit relays are highest risk** - See destination traffic; can face legal liability
4. **Bridge relays are intermediate** - Help censored users; moderate legal risk

**This project runs guard relays by default (not exit relays) for safety.**

---

### 🚨 2024-2025 Global Trends

Recent legislative shifts have increased risks in several regions:

- **The "Duty of Care" Shift:** New laws in the UK and EU are shifting focus from "passive infrastructure" to requiring operators to prevent harm, increasing administrative burdens.
- **Mandatory Registration:** Countries in Southeast Asia and Africa (Indonesia, Nigeria) are enforcing strict "service provider" registration that volunteer relays cannot meet.
- **Anti-Scam Crackdowns:** Broad "anti-fraud" laws in Thailand and Philippines are effectively criminalizing anonymity tools used by scammers, catching Tor relays in the crossfire.

---

## Legal Frameworks

### International Standards

#### United Nations

The UN recognizes internet privacy as a human right:

- **UN Resolution 68/167** - "Right to Privacy in the Digital Age"
- **Affirms:** Individuals have the right to privacy online
- **Applies to:** All member nations (193 countries)

**Impact:** International legal backing for privacy tools

#### European Union

The EU has strong privacy protections:

- **GDPR** - General Data Protection Regulation
- **Article 8** - Right to respect for private life
- **E-Privacy Directive** - Protects electronic communications

**For relay operators:** Legal to operate; can claim legitimate privacy interest

#### Internet Standards

- **RFC 7230** - Defines HTTP as transparent proxy protocol
- **Tor Design:** Follows networking standards; is a legitimate internet protocol

---

## By Country/Region

### 🟢 Generally Safe (Explicit Protection)

#### United States 🇺🇸

**Status:** Legal to run relay  
**Legal basis:** First Amendment protections, ECPA Safe Harbor provisions

**Key points:**
- Tor relay operation is explicitly legal
- Tor Project is funded by US government agencies (State Department, DARPA)
- Case law supports anonymity technology
- **EFF Legal guide:** https://www.eff.org/tor-legal

**Special note:** Running an exit relay from US may expose you to DMCA claims (third-party copyright infringement complaints). This project (guard relay) avoids this.

**Recommendation:** ✅ **Safe to operate guard relay**

---

#### European Union (General) 🇪🇺

**Status:** Legal to run relay  
**Legal basis:** GDPR, Article 8, E-Privacy Directive

**Key points:**
- GDPR explicitly permits privacy-enhancing technologies
- EU courts have upheld right to anonymity
- Running relay is considered "legitimate interest"
- Recital 49 of GDPR specifically mentions encryption and anonymity

**By country notes:**
- **Germany:** Explicit legal protection for relay operators
- **France:** Legal but may face pressure; EFF has resources
- **Netherlands:** Explicitly permitted under Dutch law
- **UK:** Legal post-Brexit under British privacy law
- **Spain:** Legally protected; courts supportive

**Recommendation:** ✅ **Safe to operate guard relay**

---

#### Norway 🇳🇴

**Status:** Safe / Regulated  
**Legal basis:** Electronic Communications Act (Ekom Act) 2025; E-Commerce Act Section 16-18

**Key points:**
- **2025 Update:** The new Ekom Act implements the EU Electronic Communications Code. While it increases registration duties for commercial providers, volunteer relays generally retain "mere conduit" liability protection.
- **Liability:** Section 16-18 of the E-Commerce Act exempts service providers from liability for transmitted content if they do not modify it.
- **Risk:** High-bandwidth exit nodes on dedicated servers might be scrutinized as "commercial" undertakings, triggering registration.

**Recommendation:** ✅ **Safe for Guard Relay; Use non-commercial status**

---

#### Canada 🇨🇦

**Status:** Legal to run relay  
**Legal basis:** Canadian Charter of Rights and Freedoms (Section 7 - privacy)

**Key points:**
- Charter protects right to privacy and security
- Canadian courts have ruled favorably on encryption
- Running Tor relay falls under privacy rights
- No laws specifically criminalizing relay operation

**Recommendation:** ✅ **Safe to operate guard relay**

---

#### Australia 🇦🇺

**Status:** Legal to run relay  
**Legal basis:** Implied constitutional right to privacy

**Key points:**
- No law explicitly prohibits relay operation
- Australian communications privacy protected
- Assistance and Access Act (TOLA) allows authorities to request technical help, but rarely targets individual relays.

**Note:** Government may investigate unusual network activity; cooperation may be required, but operation itself isn't illegal.

**Recommendation:** ✅ **Safe to operate guard relay**

---

#### Japan 🇯🇵

**Status:** Legal to run relay  
**Legal basis:** Article 21 (freedom of expression), privacy laws

**Key points:**
- Japan has strong privacy laws
- No law criminalizes relay operation
- Generally supportive of privacy tools

**Recommendation:** ✅ **Safe to operate guard relay**

---

#### New Zealand 🇳🇿

**Status:** Safe  
**Legal basis:** Telecommunications (Interception Capability and Security) Act 2013 (TICSA)

**Key points:**
- **Network Operator Definition:** TICSA obligations generally apply to large operators (ISPs). Individual volunteer relays rarely meet the threshold to be classified as a "public telecommunications network" requiring interception capability.
- **Intelligence:** As a "Five Eyes" member, traffic is monitored, but operation itself is legal.
- **ISP Terms:** The main barrier is usually ISP Terms of Service for residential connections rather than criminal law.

**Recommendation:** ✅ **Safe to operate guard relay**

---

#### Chile 🇨🇱

**Status:** Very Safe (Net Neutrality Pioneer)  
**Legal basis:** Law 20.453 (Net Neutrality), Cybersecurity Framework Law 2024

**Key points:**
- **Strong Neutrality:** Chile was the first nation to mandate Net Neutrality. ISPs are legally prohibited from arbitrarily blocking or interfering with protocols like Tor.
- **2024 Update:** The new Cybersecurity Framework Law creates a National Agency (ANCI) but focuses on "essential services" (power, water, telecom companies), leaving volunteer operators largely unregulated.

**Recommendation:** ✅ **Excellent location; Strong legal protections**

---

#### Argentina 🇦🇷

**Status:** Safe  
**Legal basis:** Supreme Court Case Law (Rodriguez v. Google)

**Key points:**
- **"Rodriguez" Doctrine:** Intermediaries are not liable for third-party content unless they have actual knowledge of a specific illegality and fail to act.
- **Tor Compatibility:** Since Guard/Exit operators cannot see content (due to encryption/onion routing), they cannot have "actual knowledge," providing a strong legal defense.
- **2025 Reform:** New data protection reforms are aligning with GDPR, further formalizing privacy rights.

**Recommendation:** ✅ **Safe to operate guard relay**

---

#### South Africa 🇿🇦

**Status:** Safe  
**Legal basis:** Electronic Communications and Transactions Act (ECTA); Cybercrimes Act 2020

**Key points:**
- **Mere Conduit:** Section 73 of ECTA provides a limited liability shield for service providers acting as "mere conduits".
- **Cybercrimes Act:** While it criminalizes hacking, it places reporting obligations primarily on large Electronic Communications Service Providers (ECSPs), not typically individual volunteers.
- **Privacy:** POPIA (Protection of Personal Information Act) encourages data minimization, which aligns with Tor's no-logs design.

**Recommendation:** ✅ **Safe to operate guard relay**

---

### 🟡 Gray Area (Legal but Cautious)

#### United Kingdom 🇬🇧

**Status:** Legal but Bureaucratic Risk  
**Legal basis:** Online Safety Act 2023 (OSA); Investigatory Powers Act 2016

**Key points:**
- **Online Safety Act 2023:** Imposes a "duty of care" on providers. While relays don't "host" content, exit nodes facilitating access to illegal sites face increased scrutiny and "collateral blocking" by ISPs.
- **Investigatory Powers:** The government has broad powers to issue "technical capability notices" or "equipment interference" warrants. While usually targeted at large Telcos, the legal scope is wide.
- **ISP Hostility:** UK ISPs actively filter "anomalous" traffic to comply with safety duties; expect account suspensions.

**Recommendation:** ⚠️ **Gray Area; Guard Relay OK on commercial hosting (not home)**

---

#### Poland 🇵🇱

**Status:** Legal but Procedural Risk  
**Legal basis:** Electronic Communications Law (ECL) 2024

**Key points:**
- **Hardware Seizure:** Police have broad powers to seize "evidence" (servers) during investigations. Operators often lose hardware for months even if innocent.
- **2024 ECL:** Distinguishes between "business activity" and volunteers. Non-commercial relays avoid data retention duties, but "commercial" definitions can be blurry.
- **Anti-Abuse:** New laws (CAEC) allow ISPs to block "abusive" traffic patterns, which often misflags Tor.

**Recommendation:** ⚠️ **Guard Relay Safe; Exit Relay High Risk (Hardware Loss)**

---

#### Brazil 🇧🇷

**Status:** Unclear; legally risky but not explicit ban  
**Legal basis:** Brazilian Civil Constitution (Article 5 - privacy rights)

**Key points:**
- No explicit law against relay operation
- Government is taking stronger internet surveillance stance
- May face pressure from authorities
- Some local hostility to anonymity tools

**Recommendation:** ⚠️ **Consult local lawyer; moderate risk for guard relay**

---

#### Colombia 🇨🇴

**Status:** Gray Area  
**Legal basis:** Habeas Data (Constitutional) vs. Police Powers

**Key points:**
- **No Safe Harbor:** Unlike Chile, Colombia lacks a specific law shielding intermediaries from liability, relying on court interpretation.
- **Enforcement:** The DIJIN (cybercrime unit) is active. Equipment seizure during investigations is a real risk if an IP is linked to a crime.
- **Data Reform 2025:** Upcoming amendments to Statutory Law 1581 may impose stricter processing definitions.

**Recommendation:** ⚠️ **Moderate Risk; Guard relay safer than Exit**

---

#### Mexico 🇲🇽

**Status:** Unclear; politically sensitive  
**Legal basis:** Constitution Article 6 (free speech, though weak)

**Key points:**
- No explicit ban on Tor relay
- Weak rule of law; government very active in surveillance
- Operating relay could trigger unwanted attention
- Context matters: government vs. criminal investigation focus
- Best practice: avoid drawing attention

**Recommendation:** ⚠️ **High risk; consult lawyer; not recommended without legal counsel**

---

#### Philippines 🇵🇭

**Status:** Gray / High Risk  
**Legal basis:** Cybercrime Prevention Act of 2012; SIM Registration Act

**Key points:**
- **Aiding & Abetting:** The law punishes "aiding" cybercrimes. Without a "safe harbor" clause, exit node operators could theoretically be charged as accomplices.
- **Cyber-Libel:** Intense focus on criminal libel makes anonymity tools politically sensitive.
- **De-anonymization:** Mandatory SIM registration removes anonymity for mobile-based connections.

**Recommendation:** ⚠️ **High Risk for Exits; Guard Relay likely okay**

---

#### India 🇮🇳

**Status:** Unclear; politically sensitive  
**Legal basis:** IT Rules (2021), CERT-In Directions

**Key points:**
- **CERT-In Rules:** VPN/Cloud providers must log user data for 5 years. Tor relays cannot comply.
- Tor is not banned, but the government is increasingly hostile to encryption.
- Citizenship Amendment Act and other laws increasing restrictions

**Recommendation:** ⚠️ **High Risk; consider hosting outside India**

---

#### Russia 🇷🇺

**Status:** Dangerous; Government Hostile  
**Legal basis:** "Sovereign Internet" laws; Roskomnadzor regulations

**Key points:**
- Public Tor relays are actively blocked by DPI (Deep Packet Inspection).
- Operating a public relay makes you a target for investigation.
- Roskomnadzor (communications regulator) actively blocks Tor
- Government takes dim view of anonymity tools
- VPN and proxy services are targeted

**Recommendation:** 🔴 **High risk; not recommended**

---

### 🔴 Dangerous (Legal Risk, Authoritarian Context)

#### Thailand 🇹🇭

**Status:** Dangerous; Functionally Illegal  
**Legal basis:** Computer Crime Act (CCA); Anti-Online Scam Decrees (2024)

**Key points:**
- **Anti-Scam Decrees:** New laws empower the "Anti-Online Scam Operation Center" (AOC) to suspend services and freeze accounts without notice for suspicious activity.
- **Liability:** Section 14 of the CCA criminalizes "inputting false data." Operators can be held liable for "consenting" to the transmission of illegal content.
- **Risk:** High probability of immediate internet termination and police investigation.

**Recommendation:** 🔴 **NOT SAFE; Do not operate**

---

#### Indonesia 🇮🇩

**Status:** Dangerous / Illegal  
**Legal basis:** Ministerial Regulation 5/2020 (PSE)

**Key points:**
- **Mandatory Registration:** All "Electronic System Providers" (PSE) must register with the Ministry (Kominfo). This requires a Tax ID and business license, making it impossible for anonymous/volunteer operators.
- **Blocking:** Unregistered services are routinely blocked (e.g., PayPal, Steam were temporarily blocked).
- **Surveillance:** Registered PSEs must provide law enforcement access, which Tor protocols cannot technically fulfill.

**Recommendation:** 🔴 **NOT SAFE; Do not operate**

---

#### Nigeria 🇳🇬

**Status:** Dangerous / High Risk  
**Legal basis:** Cybercrimes (Amendment) Act 2024

**Key points:**
- **Mandatory Retention:** The 2024 Amendment requires "service providers" to retain traffic data and subscriber info for two years.
- **Incompatibility:** Operating a Tor node (which deletes logs by design) is a direct violation of this mandatory retention law.
- **Broad Definition:** The term "service provider" is interpreted broadly to include anyone facilitating internet traffic.

**Recommendation:** 🔴 **High risk; Do not operate**

---

#### Ukraine 🇺🇦 (Martial Law Context)

**Status:** High Risk / Special Context  
**Legal basis:** Martial Law Decrees; National Security Council (NSDC)

**Key points:**
- **Dual-Use Paradox:** While Tor is used for freedom (accessing news in occupied areas), operating a relay inside government-controlled territory is risky.
- **Hostile Node:** High-bandwidth encrypted nodes may be flagged by the SBU (Security Service) as Russian sabotage/botnet infrastructure.
- **Rights Suspended:** Derogations from ECHR privacy rights are in effect due to the war.

**Recommendation:** 🔴 **High Operational Risk; Not recommended inside country**

---

#### Egypt 🇪🇬

**Status:** Illegal  
**Legal basis:** Anti-Cyber and Information Technology Crimes Law (No. 175 of 2018)

**Key points:**
- **Criminalization of Evasion:** Article 22 penalizes facilitating access to blocked websites. Running a relay is viewed as aiding censorship circumvention.
- **Active Blocking:** The government uses DPI to block OpenVPN and Tor protocols.
- **Arrest Risk:** High risk of arrest for "misuse of telecommunications."

**Recommendation:** 🔴 **NOT SAFE; Do not operate**

---

#### Turkey 🇹🇷

**Status:** Dangerous; Active Blocking  
**Legal basis:** Cybersecurity Law No. 7545 (March 2025)

**Key points:**
- **2025 Update:** New laws introduce strict penalties for "unauthorized networks."
- ISPs use DPI to throttle or block Tor and VPNs.

**Recommendation:** 🔴 **High risk; do not operate**

---

#### Vietnam 🇻🇳

**Status:** Dangerous; Data Localization  
**Legal basis:** Law on Cybersecurity (Decree 53/2022)

**Key points:**
- Requires foreign and domestic tech services to store data locally.
- Encrypted traffic is viewed with extreme suspicion.

**Recommendation:** 🔴 **NOT SAFE; do not operate**

---

#### China 🇨🇳

**Status:** Dangerous; Effectively Illegal  
**Legal basis:** CSCL and "unauthorized network" regulations

**Key points:**
- The "Great Firewall" actively hunts Tor relays.
- Operating relay would use circumvention (also illegal)
- Government actively prosecutes "unauthorized internet services"
- Operating a relay is viewed as providing "tools for circumvention."
- Human rights lawyers have faced prosecution for similar tools
- Even bridge operation is risky

**Recommendation:** 🔴 **NOT SAFE; do not operate**

---

#### Iran 🇮🇷

**Status:** Dangerous; hostile to circumvention  
**Legal basis:** Islamic Revolutionary Court rulings on "hostile networks"

**Key points:**
- Tor is blocked and circumvention is criminalized
- Operating relay would violate cybercrimes laws
- Government prosecutes for helping people circumvent censorship
- Political prisoners have been detained for tech-related offenses

**Recommendation:** 🔴 **NOT SAFE; do not operate**

---

#### Saudi Arabia 🇸🇦

**Status:** Dangerous; cybercrime laws applied aggressively  
**Legal basis:** Saudi Cybercrime Law (2007)

**Key points:**
- Anonymity tools viewed as suspicious
- Cybercrime law penalties include imprisonment
- Operating relay could be prosecuted as "assisting crime"
- Government aggressively monitors networks

**Recommendation:** 🔴 **NOT SAFE; do not operate**

---

#### Pakistan 🇵🇰

**Status:** Dangerous; government hostile  
**Legal basis:** Pakistan Telecom Authority (PTA) regulations

**Key points:**
- Tor access routinely blocked by PTA
- Operating circumvention tools is risky
- Cybercrime Ordinance broadly interpreted
- Government has prosecuted for tech activism

**Recommendation:** 🔴 **High risk; not recommended**

---

### Regional Summary Table

| Region | Guard Relay | Exit Relay | Notes |
|--------|------------|-----------|-------|
| 🇺🇸 USA | ✅ Safe | ⚠️ Risky | DMCA claims possible |
| 🇪🇺 EU | ✅ Safe | ✅ Safe | GDPR protection |
| 🇳🇴 Norway | ✅ Safe | ⚠️ Gray | 2025 Ekom Act |
| 🇨🇦 Canada | ✅ Safe | ✅ Safe | Charter protection |
| 🇦🇺 Australia | ✅ Safe | ⚠️ Gray | May require support |
| 🇯🇵 Japan | ✅ Safe | ✅ Safe | Privacy protections |
| 🇳🇿 New Zealand | ✅ Safe | ⚠️ Gray | TICSA obligations rare |
| 🇨🇱 Chile | ✅ Safe | ✅ Safe | Net neutrality pioneer |
| 🇦🇷 Argentina | ✅ Safe | ✅ Safe | Rodriguez doctrine |
| 🇿🇦 South Africa | ✅ Safe | ⚠️ Gray | ECTA protection |
| 🇬🇧 UK | ⚠️ Gray | 🔴 High | Online Safety Act |
| 🇵🇱 Poland | ⚠️ Gray | 🔴 High | Hardware seizure risk |
| 🇧🇷 Brazil | ⚠️ Gray | 🔴 High | Consult lawyer |
| 🇨🇴 Colombia | ⚠️ Gray | 🔴 High | No safe harbor |
| 🇲🇽 Mexico | ⚠️ Gray | 🔴 High | Weak rule of law |
| 🇵🇭 Philippines | ⚠️ Gray | 🔴 High | Aiding & abetting risk |
| 🇮🇳 India | ⚠️ Gray | 🔴 High | Growing hostility |
| 🇷🇺 Russia | ⚠️ Gray | 🔴 Very High | Blocked network |
| 🇹🇭 Thailand | 🔴 No | 🔴 No | Anti-scam decrees |
| 🇮🇩 Indonesia | 🔴 No | 🔴 No | Mandatory registration |
| 🇳🇬 Nigeria | 🔴 No | 🔴 No | Data retention law |
| 🇺🇦 Ukraine | 🔴 No | 🔴 No | Martial law context |
| 🇪🇬 Egypt | 🔴 No | 🔴 No | Criminalized |
| 🇹🇷 Turkey | 🔴 No | 🔴 No | Active blocking |
| 🇻🇳 Vietnam | 🔴 No | 🔴 No | Data localization |
| 🇨🇳 China | 🔴 No | 🔴 No | Criminalized |
| 🇮🇷 Iran | 🔴 No | 🔴 No | Blocked + hostile |
| 🇸🇦 Saudi Arabia | 🔴 No | 🔴 No | Aggressive enforcement |
| 🇵🇰 Pakistan | 🔴 No | 🔴 No | PTA blocking |

---

## Relay Type Differences

### Guard Relay (Recommended)

**What:** Entry node for Tor users  
**Legal Risk:** **Minimal**

**Why safest:**
- Never sees destination addresses
- Never sees onion site content
- Cannot be traced to user's real destination
- Simply transmits encrypted packets
- Cannot identify what users are doing

**Legal basis:**
- In most countries, relay operation itself is legal
- No content visibility = no copyright/hosting liability
- Act of relaying is neutral infrastructure

**Recommendation:** ✅ **This project's default choice**

---

### Exit Relay

**What:** Final node before traffic reaches destination  
**Legal Risk:** **High**

**Why risky:**
- Sees destination traffic in unencrypted form
- Can be held liable for illegal content routed through
- Exit IP appears as source to destination servers
- May receive DMCA, abuse complaints, law enforcement requests

**Legal liability:**
- If child exploitation detected, may have reporting obligations
- Copyright holders send DMCA notices to exit IP
- Law enforcement may investigate for criminal traffic

**Recommendation:** ❌ **Not recommended unless you understand risks**

---

### Bridge Relay

**What:** Hidden relay for censored users  
**Legal Risk:** **Moderate**

**Why moderate:**
- Helps people circumvent censorship
- Governments may view negatively
- Users are typically circumventing censorship, not committing crimes
- Legal status depends on local government attitude

**Recommendation:** ⚠️ **Safe in democracies, risky in autocracies**

---

## Liability & Protection

### What You Are Responsible For

**As a relay operator, you are responsible for:**

1. **Understanding local laws** - Know your jurisdiction's position
2. **ISP compliance** - Follow your ISP's terms of service
3. **Configuration safety** - Don't run exit relay if unsure
4. **Responding to legal requests** - Cooperate with law enforcement (if legally required)

### What You Are NOT Responsible For

**You cannot be held liable for:**

1. **Content routed through your relay** - Just like postal service isn't liable for mail contents
2. **What users do with Tor** - You don't control usage
3. **Third-party crimes** - Tor itself isn't illegal
4. **User misconduct** - You don't monitor or enforce user behavior

**Legal basis:** Common carrier protection (applies in most democracies)

---

### Legal Protections

#### United States

**Safe Harbor Provisions:**
- **47 U.S.C. § 230** - Platform immunity (applies to infrastructure)
- **First Amendment** - Protects right to operate anonymity tools
- **EFF Case Law** - Multiple favorable precedents

**Takeaway:** Relay operation has explicit legal protection

#### European Union

**GDPR Protections:**
- **Article 8** - Right to privacy
- **Recital 49** - Explicitly permits anonymity and encryption
- **Case law:** Multiple EU courts have upheld relay operation

**Takeaway:** Operating relay is recognized legitimate interest

---

## Best Practices

### ✅ Legal Safeguards

**Before operating relay:**

1. **Know your laws** - Research your country's specific laws
2. **Check ISP terms** - Some ISPs prohibit relay operation
3. **Consult lawyer if unsure** - Especially outside democracies
4. **Document intent** - Record why you're running relay (humanitarian/research)
5. **Keep configuration clean** - Run guard relay, not exit relay

### During Operation

1. **Respond to queries** - ISPs may ask questions; respond honestly
2. **Monitor legal landscape** - Subscribe to EFF updates
3. **Document changes** - Keep configuration history
4. **Use contact info** - Provide accurate contact information in relay config
5. **Maintain logs** - For your own defense; logs usually don't identify users

### Configuration Recommendations

```conf
# Use real contact info (helps with abuse handling)
Nickname YourRelayName
ContactInfo your-email@example.com <0xPGP_FINGERPRINT>

# DO NOT run exit relay unless you know what you're doing
ExitRelay 0
ExitPolicy reject *:*

# Log properly for your own records
Log notice file /var/log/tor/notices.log
```

### 📢 Transparency & Exit Notices

If you choose to run an **Exit Relay** (high risk), it is **critical** to run a web server on your relay's IP address (Port 80) that serves an "Exit Notice."

**Why this helps legally:**
1.  **Immediate Context:** When a sysadmin sees "attacking" traffic from your IP, their first step is often to type your IP into a browser.
2.  **Reduces Abuse Reports:** If they see a professional notice explaining that this is a Tor Exit Node (and not a hacker's machine), they often discard the complaint immediately.
3.  **Safe Harbor:** It explicitly states your status as a common carrier/infrastructure provider.

**Implementation:**
Add this to your `torrc`:
```conf
DirPort 80
DirPortFrontPage /etc/tor/index.html
```

> Privacy-friendly Exit Notice Template that you can use can be found in [`templates/tor-exit-notice`](/templates/tor-exit-notice/).
> Make sure to change your exit node's IP/contact info.

---

## Abuse Handling

### If You Receive an Abuse Complaint

**Step 1: Don't Panic**
- Abuse complaints are normal for relay operators
- Most are routine and don't require action
- You're not liable for content routed through

**Step 2: Verify the Complaint**
- Confirm it's actually from your relay
- Check source IP matches your ORPort
- Review Tor Metrics for your fingerprint

**Step 3: Understand Tor's Role**
- Explain Tor routing to complainant
- Your relay doesn't control traffic destination
- You only transmit encrypted packets

**Step 4: Respond Professionally**
- Use EFF response template (see below)
- Keep response factual and brief
- Don't admit wrongdoing
- Provide Tor Project resources

**Step 5: Document Everything**
- Save complaint emails
- Record your responses
- Keep for potential legal defense

---

### Example Response (DMCA Notice)

**EFF Template for Copyright Claims:**

```
Thank you for your complaint regarding [your relay IP].

Our network operates a Tor relay node. Tor is a legitimate anonymity 
network used by journalists, activists, and privacy advocates worldwide.

As a relay operator, we:
- Do not control traffic routing
- Cannot identify content being transmitted
- Transmit encrypted packets without inspection
- Are not responsible for third-party use

Per USC 17 § 512(a), network operators cannot be held liable for 
transient communication of copyrighted material not originated by us.

For more information:
- Tor Project: https://www.torproject.org
- EFF Legal FAQ: https://www.eff.org/tor-legal
- Common Carrier Doctrine: [relevant case citation]

Best regards,
[Your Name]
```

---

### If Law Enforcement Contacts You

**General principles:**

1. **Don't panic** - Tor operation isn't criminal in most countries
2. **Stay calm** - Cooperation is usually required anyway
3. **Know your rights** - You may have attorney-client privilege
4. **Ask for specifics** - What are they investigating?
5. **Consult lawyer** - If you're uncertain, get legal counsel

**What to expect:**

- They may request logs (which rarely identify users in Tor relays)
- They may ask about your relay's purpose
- They may seek information about users (which you don't have)
- Most Tor inquiries are routine, not investigations

**What you can legitimately say:**

```
"I operate a Tor guard relay as part of internet infrastructure. 
The relay is configured to not see user traffic destinations or 
onion service activity. I maintain logs of my own operations but 
cannot identify users or their activity."
```

---

## Legal Resources

### Organizations

- **Electronic Frontier Foundation (EFF)** - https://www.eff.org
  - Legal guide for Tor operators
  - Case law resources
  - FAQ on relay legality

- **Tor Project** - https://www.torproject.org
  - Official relay guidelines
  - Legal considerations
  - Community resources

- **Access Now** - https://www.accessnow.org
  - Internet freedom advocacy
  - Helps with legal threats

- **Freedom of the Press Foundation** - https://freedom.press
  - Legal resources for activists
  - Supports at-risk