# AstraLife — แผนพัฒนาจาก V0.5 สู่โลกของตัวแทนอัจฉริยะที่ร่วมมือเพื่ออยู่รอด

วันที่: 5 กันยายน 2026 | ฉบับขยายสำหรับ PR | สถานะ: แผนเสนอเพื่อพัฒนา ยังไม่ได้แก้โค้ดหรือทดสอบ runtime

> ลำดับการรวมงาน: main ยังเป็น V0.5; PR #1 เป็น V0.5.1 Core Architecture Hardening ที่ยังเปิดอยู่ ณ เวลาจัดทำ แผนนี้รับช่วงงานดังกล่าว ไม่สร้าง WorldStateBoundary, AgentStateBoundary หรือ Decision Staging ซ้ำ งาน Memory + Belief ที่เรียก V0.5.1 ใน roadmap หมายถึง workstream ต่อจาก core hardening; ถ้า V0.5.1 release แล้วให้ใช้เลข patch ถัดไปตาม release จริง โดยไม่เปลี่ยน dependency ของงาน

## 1. เป้าหมายและขอบเขต

สร้างโลกที่เปิดดูและโต้ตอบผ่าน HTML โดยมนุษย์ทุกคนมีตัวตน session ความจำ ความเชื่อ แบบจำลองโลก เป้าหมาย และการตัดสินใจของตนเอง การรวมกลุ่ม แบ่งงาน และความเชี่ยวชาญเกิดจากประสบการณ์และการเจรจา ภายใต้โลกที่มีข้อจำกัดจริงจนคนเดียวทำทุกอย่างไม่ทัน

คำว่า “แนวทาง Astra” ในเอกสารนี้หมายถึงสถาปัตยกรรมของ AstraLife ที่เราออกแบบ: Observe → Model → Predict → Plan → Act → Verify → Learn ไม่ใช่ข้อยืนยันเกี่ยวกับสถาปัตยกรรมภายในที่ไม่เปิดเผยของโมเดล Astra

เป้าหมายปลายทางคือทุกคนเรียก Astra provider ด้วยบริบทแยกกันเมื่อจำเป็นต้องคิด ไม่จำเป็นต้องมีสำเนาน้ำหนักโมเดลหรือ process แยกต่อคน แต่ต้องไม่มีการปะปนของ session และข้อมูลส่วนตัวระหว่างคน การใช้ local/sim ระหว่างพัฒนาเป็นโหมดทดสอบ ต้องแสดงว่าไม่ใช่ Astra จริง

## 2. ฐานที่ตรวจพบ

ตรวจ README, index.html และโค้ดส่วน memory/observation, provider simulator และ V0.5 extension จาก default branch ณ วันที่จัดทำ ไม่ใช่การ audit ทั้ง repository และยังไม่ได้รันระบบ

| ฐานปัจจุบัน | ผลต่อแผน |
| --- | --- |
| README ระบุ V0.5 Emergent Roles + Skill Learning | พัฒนาต่อแบบ incremental ห้ามสร้าง simulator ใหม่หรือทิ้งความสามารถเดิม |
| ทุกคนเริ่ม Human/generalist มี competency, preference, reputation และผลสำเร็จ/ล้มเหลว | รักษากฎนี้ ห้ามแจกอาชีพสำเร็จรูปตอนเกิด |
| มี facts, memory, trust และ providerSessionId แยกต่อคน | เพิ่มโครงสร้างและความถูกต้องจากฐานเดิม |
| มี partial observation และ pipeline ENVIRONMENT → OBSERVE → REQUEST → PROVIDER → VALIDATE → RESOLVE → LEARN → COMMIT | รักษาโลกเป็นผู้ตัดสินผลจริง |
| astra-sim ใช้โค้ดเงื่อนไขตัดสินใจ | ไม่ใช้การเลือกโหมดนี้เป็นหลักฐานว่าเชื่อม Astra จริง |
| memory compaction ย่อเป็นจำนวนเหตุการณ์แต่ละชนิด | เปลี่ยนให้เก็บข้อเท็จจริงที่สำคัญ เหตุผล ผลลัพธ์ และแหล่งหลักฐาน |
| สร้างที่พักต้องมีอย่างน้อยสองคนอยู่ร่วมงาน | มีจุดเริ่มต้นความร่วมมือแล้ว เพิ่มการนัดหมายและวัดผล |
| V0.5 ใช้ prototype overrides และยังมีข้อความ V0.4 ใน HTML ก่อน script ปรับ | ระวังจุด override ตอนแก้ และจัด version metadata ให้สอดคล้องโดยไม่ redesign UI |

จุดตรวจเร่งด่วน: MemorySystem อ่าน credibility จาก state.agentById และ planner/provider ใช้ยอด alive ของทั้งโลก ต้องกำหนดว่าข้อมูลใดเป็นสาธารณะ ถ้าไม่สาธารณะต้องเปลี่ยนเป็นสิ่งที่ agent สังเกตหรือได้รับรายงานจริง รวมถึงทบทวนการเปิดเผย stormTicks แบบแม่นยำ

## 3. กฎสถาปัตยกรรมที่ล็อก

1. World Runtime เป็นเจ้าของ world truth และการ commit ผลเพียงแห่งเดียว Provider ส่งคำขอกระทำ ไม่มีสิทธิ์แก้โลกโดยตรง
2. Agent รู้จาก observation ของตน ความจำ และข้อความที่ส่งถึงตนเท่านั้น ข้อมูลเริ่มต้นร่วมกันต้องระบุชัด เช่น ตำแหน่งค่าย
3. ความเชื่อไม่เท่ากับความจริง ข่าวจากคนอื่นต้องมีผู้ให้ข่าว เวลา หลักฐาน ความมั่นใจ และวันหมดอายุ
4. ทุกคนยังตัดสินใจเอง Coordinator เป็นคนที่เสนอแผนและได้รับการยอมรับ ไม่มีสิทธิ์เขียน goal ให้คนอื่นโดยตรง
5. โลกเดินด้วย fixed tick; การคิดของโมเดลเกิดตามเหตุการณ์และงบ ไม่เรียกทุกเฟรม
6. Action ที่มาช้าต้องตรวจความเกี่ยวข้องใหม่ ตรวจระยะ เป้าหมาย ทรัพยากร ความมีชีวิต และเงื่อนไขก่อนลงมือ
7. การเรียนรู้ใน runtime หมายถึงการปรับ memory/belief/skill/policy ของ agent ไม่อ้างว่าปรับน้ำหนักโมเดลอัตโนมัติ
8. เก็บ save schema version และ migration; checkpoint เก่าที่รองรับต้องเปิดได้โดยไม่ทำตัวตนและทักษะสูญหาย
9. Replay ที่มี provider ภายนอกใช้บันทึกคำตอบและเวลารับคำตอบ ไม่อ้างว่าเรียกโมเดลใหม่แล้วจะได้ผลเหมือนเดิมจาก seed เดียว

## 4. โครงสร้างระบบเป้าหมาย

HTML/Canvas รับ input ผู้ชมและแสดง snapshot ส่วน simulation แยกจาก renderer เริ่มใช้ runtime เดิมแล้วค่อยย้ายงานคำนวณไป Worker หรือ backend ตามหลักฐานด้านประสิทธิภาพ เมื่อใช้ provider จริงให้มี backend bridge เก็บ credential และจัดคิว

| องค์ประกอบ | หน้าที่ |
| --- | --- |
| World Runtime | เวลา ทรัพยากร ร่างกาย อากาศ กติกา และผลลัพธ์จริง |
| Observation Builder | สร้างข้อมูลเฉพาะที่แต่ละคนมีสิทธิ์รับรู้ |
| Agent Mind | ความจำ ความเชื่อ world model goal plan และความสัมพันธ์ |
| Decision Scheduler | เลือกว่าใครควรคิดเมื่อใด จำกัด concurrent calls และงบ |
| Provider Adapter | ส่งบริบทเฉพาะคน ตรวจ request/response และจัดการ timeout |
| Validator + Resolver | ตรวจคำสั่ง จัดลำดับ แก้การแข่งขันใช้ทรัพยากร และคืน outcome |
| Learning System | เทียบ prediction กับ outcome ที่รับรู้ได้ แล้วปรับความเชื่อ/ทักษะ |
| Inspector + Replay | แสดงหลักฐานการตัดสินใจ เหตุการณ์ และผลการทดลอง |

การแยกไฟล์เป็นข้อเสนอเรื่องความรับผิดชอบ ต้องตรวจ call graph และ AGENTS.md ก่อนเลือกตำแหน่งแก้จริง ไม่จำเป็นต้องแตกไฟล์ใหม่ทุกองค์ประกอบ

## 5. สัญญาข้อมูลต่อมนุษย์หนึ่งคน

| ส่วน | ข้อมูลขั้นต่ำ |
| --- | --- |
| Identity | agentId, simulationId, sessionId, schemaVersion |
| Body | สุขภาพ ความหิว กระหาย พลังงาน สัมภาระ |
| Memory | episodeId, observedTick, event, action, perceivedOutcome, evidenceIds, importance |
| Belief | beliefId, claim, source, observedTick, receivedTick, confidence, expiry, status |
| World Model | แหล่งทรัพยากรที่รู้ เส้นทางที่รู้ บุคคลที่รู้ และสมมติฐานความสัมพันธ์เหตุ–ผล |
| Goal/Plan | เป้าหมาย ลำดับงาน prerequisites เงื่อนไขสำเร็จ/เลิก และเวลาทบทวน |
| Prediction | expectedOutcome, horizon, confidence, assumptions, evidenceIds |
| Social | inbox, localTrust, promises, teamMembership, knowledgeProvenance |
| Development | competency, experience, preference, domainReputation, success/failure |
| Runtime | pendingRequestId, observationVersion, deadline, providerUsed, fallbackReason |

เก็บความเชื่อที่ขัดกันได้ ไม่ให้ข่าวใหม่เขียนทับอัตโนมัติเพียงเพราะ confidence สูงกว่า แยกสถานะ unverified/confirmed/stale/refuted และไม่เพิ่มความมั่นใจจากข่าวต้นทางเดียวที่ถูกส่งวนหลายครั้ง

## 6. Roadmap และเกณฑ์ผ่าน

### V0.5.1 — ความจำ ความเชื่อ และขอบเขตข้อมูล

- ตรวจฐาน release และ overrides; บันทึก baseline scenario, seed, schema และผลเดิมก่อนแก้
- เพิ่ม structured episodes และสรุปบทเรียนที่รักษา evidence แทนการเก็บเพียงจำนวนประเภทเหตุการณ์
- แยก direct observation ออกจากรายงาน; เพิ่ม provenance, expiry และการจัดการความขัดแย้ง
- ปิดทางลัดอ่านความจริงส่วนกลางในเส้นทางคิดของ agent เว้นข้อมูลสาธารณะที่ประกาศไว้
- เพิ่ม migration และแผงดู belief/evidence ใน Inspector เดิม
- แก้การตรวจข่าว: แหล่งน้ำหมดภายหลังไม่ได้แปลว่าผู้รายงานโกหก แยก outdated, mistaken และ contradicted; ความผิดครั้งเดียวไม่พออนุมานเจตนา

เกณฑ์ผ่าน: A พบแหล่งน้ำ B ไม่รู้จนได้รับข่าว; ข้อมูลที่อยู่นอกการรับรู้และไม่กระทบ observation ต้องไม่เปลี่ยน request ของ B; ข่าวเก่าหมดอายุและแก้เมื่อพบหลักฐาน; ความจำย่อยังดึงบทเรียนสำคัญกลับมาได้; save/load และความสามารถ V0.5 ยังผ่าน

### V0.5.2 — World Model ที่ใช้คาดการณ์ได้

- เริ่มความสัมพันธ์เล็ก ๆ เช่น ระยะทางกับพลังงาน งานก่อสร้างกับขนาดทีม และความเสี่ยงจากที่พักไม่พอ
- ก่อนทำงานสำคัญให้เก็บ prediction พร้อม assumptions
- หลังทำเทียบผลที่ agent รับรู้ได้กับที่คาด ปรับค่าประมาณและ confidence พร้อมเก็บข้อยกเว้น
- Prediction เป็นแบบจำลองโดยประมาณ ไม่เรียก world truth เพื่อแอบทดลองคำตอบ

เกณฑ์ผ่าน: เปลี่ยนตำแหน่งน้ำหรือผลกระทบอากาศแล้ว agent ปรับแผนจากประสบการณ์; รายงาน prediction error ก่อน/หลังการเรียนรู้พร้อมจำนวนตัวอย่าง; ข่าวผิดไม่ทำให้วนหาเป้าหมายเดิมไม่สิ้นสุด

### V0.6 — แผนหลายขั้นและการเรียนรู้จากความผิดพลาด

- เปลี่ยน plan ที่เป็นข้อความให้มีขั้นตอนและ prerequisites ตรวจได้
- ตัวอย่าง: สำรวจ → ยืนยันน้ำ → แจ้งข่าว → รับงานขน → ส่งของ → ตรวจว่างานสำเร็จ
- รองรับ interrupt เมื่อหิวมาก บาดเจ็บ เป้าหมายหมด หรือสมาชิกถอนตัว
- เพิ่ม stuck detector และการเปลี่ยนวิธีเมื่อผิดซ้ำ ไม่เพิ่มรางวัลจากการทำผิดซ้ำโดยไม่มีประโยชน์
- คง skill learning เดิมและเพิ่มบทเรียนเชิงกลยุทธ์ โดยแยกค่ากติกาการฝึกจากข้อสรุปที่ agent เรียนเอง

เกณฑ์ผ่าน: บรรลุเป้าหมายหลายขั้นได้; เปลี่ยนเงื่อนไขกลางงานแล้ว replan; ตรวจพบและหยุด loop ที่ไม่ก้าวหน้า

### V0.7 — ความร่วมมือที่มีพันธะและต้นทุน

- เพิ่ม offer/accept/decline/cancel/completed เป็นสถานะของงานร่วม มีผู้รับผิดชอบ deadline และสิ่งที่ต้องรอ
- ขยาย ASK/REPORT/REQUEST_HELP/OFFER/WARN เดิมอย่างมี version ของ contract
- เพิ่มงานที่พึ่งพากันจริง เช่น สร้างที่พักเป็นทีม ขนของกับคนดูแลผู้บาดเจ็บ เตรียมเสบียงก่อนพายุ
- ให้สมาชิกตอบรับเอง งานล้มได้ เจรจาใหม่ได้ และคำสัญญาต้องตรวจจากผลจริง
- ข้อมูล reputation ของผู้อื่นต้องได้จากประสบการณ์หรือช่องทางข่าวที่กำหนด ไม่อ่านคะแนนลับส่วนกลาง

เกณฑ์ผ่าน: ทีมรวมตัวทำงานสำเร็จได้โดยไม่มีผู้ควบคุมกำหนดอาชีพ; เมื่อคนหนึ่งถอนตัวทีมปรับแผนได้; ปิดการประสานงานแล้วความอยู่รอดลดลงอย่างวัดได้บน scenario และงบเดียวกัน

### V0.8 — Astra provider จริงพร้อม session isolation

- ตรวจช่องทางเรียก Astra ที่ได้รับอนุญาตและมีอยู่จริงก่อน implementation ไม่สมมติว่าชื่อโมเดลในแอปเป็น API ที่เรียกได้
- Bridge รับเฉพาะ agent context ที่ผ่าน observation boundary; แยกประวัติตาม simulationId/agentId/sessionId
- Strict schema, correlation IDs, timeout, cancellation, deduplication, stale response rejection และ idempotent action handling
- ระบุ provider จริงที่ใช้ต่อ decision; โหมด strict Astra ถ้าเรียกไม่ได้ต้องแสดง paused/unavailable; โหมด resilient อนุญาต local fallback แต่ติดป้ายชัด
- ทดสอบ 5–10 คนก่อน ทุกคนมี trace เชื่อม request → response → accepted action → outcome

เกณฑ์ผ่าน: session ไม่ปะปน; request เก่าไม่ข้ามเข้าโลกหลัง reset; คำสั่งซ้ำไม่เกิดผลสองครั้ง; จำลอง timeout/429 แล้วระบบคุมงบและแสดงสถานะถูกต้อง; ถ้ายังไม่มีช่องทาง Astra จริงให้ระบุ gate ว่ายังไม่ผ่าน

### V0.9 — เพิ่มประชากรและความต่อเนื่อง

- ขยายเป้าทดลอง 20 → 50 → 100 → 300 คน โดยแต่ละขั้นผ่านงบ เวลา และ isolation ก่อน ตัวเลขเหล่านี้เป็นเป้าทดสอบ ไม่ใช่ความสามารถที่รับรองแล้ว
- การเดินและทำแผนเดิมใช้ executor ปกติ; เรียกคิดใหม่เมื่อข้อมูลสำคัญเปลี่ยนหรือแผนล้ม
- Fair scheduling และ maximum wait ป้องกันคนความสำคัญต่ำไม่ได้คิดตลอดไป
- แยก simulation จาก render; เพิ่ม spatial index และ bounded memory เมื่อ profiling ชี้ว่าจำเป็น
- Snapshot + event log + provider response log; restore pending request อย่างชัดเจนโดยไม่ยิง action ซ้ำ

สูตรวางงบ: calls/minute = N × r; tokens/minute ≈ N × r × (inputTokens + outputTokens) โดย r คืออัตราคิดเฉลี่ยต่อคนต่อนาที ต้องนับ retries และตั้ง hard cap ด้วย ราคาจริงและ quota ตรวจเมื่อเลือก provider

เกณฑ์ผ่าน: รายงาน p95 tick time, decision latency, starvation, token usage และ frame rate พร้อมอุปกรณ์ทดสอบ; restore แล้วตัวตน/ความจำคงอยู่; จำนวนคนเพิ่มไม่ทำให้ session รวมกัน

### V1.0 — พิสูจน์สังคมเอาชีวิตรอด

- โลกย่อยเริ่มต้นมีมนุษย์ 20 คน น้ำ/อาหารกระจาย ที่พักจำกัด พายุ และคนบาดเจ็บ
- ทดลองหลาย seed ด้วย scenario version เดียวกัน มีโหมดสื่อสารปกติ/ปิดสื่อสาร/ปิด learning/ปิด prediction
- กำหนดจำนวนรอบ ช่วงเวลาวัด และเกณฑ์สำเร็จก่อนรัน แยก tuning seeds กับ evaluation seeds
- จัดทำ replay ตัวอย่างว่าพบปัญหา แลกข้อมูล นัดหมาย ลงมือ และเรียนรู้อย่างไร

เกณฑ์ผ่าน: ยืนยันประโยชน์ด้านอัตรารอดและความขาดแคลนจากการทดลอง ไม่สรุปจากภาพตัวละครคุยกันหรือจำนวนข้อความ; รายงานความแปรปรวนและรอบที่ล้มเหลวด้วย

## 7. มาตรวัดหลัก

| คำถาม | มาตรวัด |
| --- | --- |
| อยู่รอดดีขึ้นหรือไม่ | อัตรารอดที่ tick/day กำหนด เวลาเฉลี่ยก่อนตาย ชั่วโมงขาดน้ำ/อาหาร |
| ร่วมมือเกิดผลหรือไม่ | งานร่วมที่สำเร็จ เวลาช่วยคน ข้อตกลงที่ทำสำเร็จ/ผิดนัด |
| เรียนรู้หรือไม่ | ความผิดพลาดซ้ำ prediction error การแก้ความเชื่อเมื่อโลกเปลี่ยน |
| ตัวตนอิสระหรือไม่ | cross-session contamination และ hidden-state leakage ต้องเป็นศูนย์ในชุดทดสอบ |
| ขยายได้หรือไม่ | p95 tick/decision latency, calls, tokens, peak memory, จำนวน agent ที่รอเกินกำหนด |

ห้ามใช้ role diversity, XP หรือข้อความอธิบายเหตุผลเพียงอย่างเดียวเป็นหลักฐานความฉลาด ต้องเชื่อมกับผลลัพธ์จริง

## 8. งานชุดแรกที่ส่งให้ผู้พัฒนาได้

Mission: V0.5.1 Memory + Belief Integrity

1. ยืนยัน HEAD และอ่านข้อกำหนด repository; ตรวจ save schema, test command และลำดับ overrides
2. ทำ baseline และ regression scenarios ของ V0.5
3. เพิ่ม structured memory/belief และ migration แบบ additive
4. ปรับ memory compaction ให้รักษาบทเรียนพร้อมหลักฐาน
5. ตรวจและแก้ hidden world-state access ใน cognitive path โดยประกาศ public knowledge ชัด
6. เพิ่ม Inspector เฉพาะข้อมูลใหม่และอัปเดต version ที่จำเป็น
7. ส่ง diff, architecture note, migration note, รายงานทดสอบ และ known limitations

พื้นที่โค้ดที่ต้องตรวจ: js/02-memory-observation.js, js/03-planner.js, js/04-provider-core.js, js/05-provider-sim-remote.js, js/10-world-runtime.js, js/11-ui-runtime.js และ overrides ใน js/14-emergent-roles-v05.js ตำแหน่งนี้เป็นแผนตรวจ ไม่ใช่ข้อสรุปว่าต้องแก้ทุกไฟล์

นอกขอบเขต mission แรก: rewrite, UI redesign, ระบบเมือง/การเมือง/เศรษฐกิจใหญ่, เพิ่มประชากรครั้งใหญ่ หรือเชื่อม API โดยไม่มีช่องทางที่ยืนยันได้

จุดส่งมอบที่ผู้ใช้ควรเห็น: เลือกมนุษย์สองคนแล้วตรวจได้ว่ารู้ต่างกัน ใครเล่าข่าวให้ใคร ข่าวนั้นมีอายุเท่าไร และอะไรทำให้แต่ละคนเปลี่ยนใจ

## 9. แหล่งอ้างอิงฐานโปรเจกต์

- https://github.com/nustanakritwithai/AstraLife/blob/main/README.md
- https://github.com/nustanakritwithai/AstraLife/blob/main/index.html
- https://github.com/nustanakritwithai/AstraLife/blob/main/js/02-memory-observation.js
- https://github.com/nustanakritwithai/AstraLife/blob/main/js/05-provider-sim-remote.js
- https://github.com/nustanakritwithai/AstraLife/blob/main/js/14-emergent-roles-v05.js

แหล่งข้างต้นรองรับสถานะโค้ดที่ตรวจพบ ส่วน roadmap โครงสร้างข้อมูลและเกณฑ์ผ่านเป็นข้อเสนอใหม่ของเอกสารนี้

## 10. การรับช่วง PR #1 และป้องกันระบบซ้ำ

ตรวจ PR #1 ที่ head `acf195cf76b70e427d463d89597e1fd62ec1e9d3` รวมถึง `js/core/contracts-v051.js` และ `js/core/agent-state-v051.js` แผนนี้ไม่ถือว่าการมีชุดทดสอบใน PR เท่ากับรันทดสอบผ่านแล้ว

| งานใน PR #1 | แผนรับช่วง | สิ่งที่ยังต้องพิสูจน์ |
| --- | --- | --- |
| WorldStateBoundaryV051 | ใช้เป็น snapshot boundary เดิม | snapshot isolation และการแยก truth ออกจาก observation |
| AgentStateBoundaryV051 | ขยาย persistent view และเพิ่ม restore/migration | persistent() export อย่างเดียวไม่ใช่ save/load ครบวงจร |
| Decision Staging | ใช้ lifecycle และ rejection feedback เดิม | duplicate, reset epoch, stale result และการแก้แผน |
| astra.* core contracts | ทำ compatibility mapping จาก astra-colony.* | ข้อมูลใหม่ต้องมี schema version ที่ตกลง ไม่เพิ่ม field ขัด additionalProperties:false |
| Acceptance harness | ใช้ regression suite เดิมและเพิ่ม behavioral cases | รันจริง เก็บ seed/commit/result ไม่คัดลอกคำอ้างว่าผ่าน |

PR เอกสารนี้ merge ได้แยกจาก PR #1 เพราะไม่แก้ runtime แต่ implementation ของ memory/belief ต้องเริ่มจากฐานที่รวม core hardening แล้ว หรือทบทวนข้อตกลงใหม่หาก PR #1 เปลี่ยน/ถูกปิด ห้าม cherry-pick โมดูลซ้ำเข้ามาหลายรอบ

Sources: [PR #1](https://github.com/nustanakritwithai/AstraLife/pull/1), [core contracts ที่ตรวจ](https://github.com/nustanakritwithai/AstraLife/blob/acf195cf76b70e427d463d89597e1fd62ec1e9d3/js/core/contracts-v051.js), [agent boundary ที่ตรวจ](https://github.com/nustanakritwithai/AstraLife/blob/acf195cf76b70e427d463d89597e1fd62ec1e9d3/js/core/agent-state-v051.js)

## 11. Ownership และขอบเขตความรู้ที่ตรวจได้

| ข้อมูล | ผู้เขียน | ผู้ใช้ที่อ่านได้ |
| --- | --- | --- |
| ร่างกาย/ทรัพยากร/อากาศจริง | World systems และ resolver ตาม phase | Runtime; ผู้ชมผ่าน snapshot; agent ผ่าน observation เท่านั้น |
| Observation | Observation Builder | เจ้าของ observation และ validator |
| Belief / memory / skill lesson | Cognitive learning ของเจ้าของ | เจ้าของ; ผู้ชมใน Inspector; คนอื่นเฉพาะที่ส่งผ่านข้อความ |
| Accepted action / outcome | Validator / Resolver | Runtime และ agent ที่มีสิทธิ์รับรู้ผล |
| ความไว้วางใจของ A ต่อ B | Learning ของ A | A; ไม่ broadcast โดยอัตโนมัติ |
| คะแนนสังคมรวมสำหรับวิเคราะห์ | Evaluation system | Dashboard ผู้ชม ไม่ใช้เป็นคำตอบลับของ agent |
| Team commitment | Protocol service บันทึกการตอบรับจริง | สมาชิกหรือผู้ได้รับข้อความตามกติกา |

Public knowledge เริ่มต้นที่เสนอ: ตำแหน่งค่ายและกฎพื้นฐานการกระทำ ส่วนประชากรที่ยังมีชีวิต สต็อกค่ายนอกระยะ ตำแหน่งทรัพยากร และเวลาจบพายุไม่เป็น global truth ที่แจกให้ทุกคน หากต้องมีการประกาศยอดคนหรือสต็อก ให้ผ่านกระดาน/รายงานพร้อมเวลาสำรวจและโอกาสคลาดเคลื่อน

Observation รวม own body, สิ่งที่มองเห็น, ข้อความที่ส่งถึง และเหตุการณ์ที่รับรู้ได้ การตัดสินใจข้าม tick ใช้ observationId เดิมระบุที่มา แต่ต้องตรวจเงื่อนไขปัจจุบันอีกครั้ง Learning รับ perceived outcome; full resolver diagnostics เก็บสำหรับผู้พัฒนาโดยไม่หลุดไปบอกข้อมูลที่ agent ไม่มีทางทราบ

## 12. Tick และการคิดแบบ asynchronous

1. ENVIRONMENT: อัปเดตอากาศ ความต้องการ และทรัพยากรด้วย RNG ที่ควบคุมได้
2. OBSERVE: ส่งผลที่รับรู้ได้จากรอบก่อนและสร้าง immutable observation ของแต่ละคน
3. REQUEST: ดึง memory เฉพาะที่เกี่ยวข้อง; สร้าง request พร้อม simulationId, runEpoch, agentId, sessionId, requestId, observationId และ deadlineTick
4. PROVIDER: รับคำตอบที่เสร็จแล้วเข้าช่อง staging; request ที่ยังไม่เสร็จไม่หยุด render หรือบังคับโลกทั้งหมดรอ
5. VALIDATE: ตรวจ schema, identity, epoch, deadline, target และเงื่อนไข; provider ไม่มีสิทธิ์ตั้ง validated=true เพื่อข้ามขั้นนี้
6. RESOLVE: ตัดสิน action ที่รับแล้วในลำดับคงที่; ตรวจทรัพยากรซ้ำเมื่อจะใช้จริง; ใช้ resource reservation หรือ atomic debit ป้องกันสองคนเบิกของชิ้นเดียว
7. LEARN: เจ้าของรับ feedback ที่กรองแล้ว เทียบ prediction เมื่อครบ horizon และปรับ memory/belief
8. COMMIT: บันทึกผลและ snapshot รอบนั้นก่อนส่ง renderer; การเปลี่ยนแปลงช่วงก่อนหน้าถือเป็น working state ของ tick

ลำดับ action ต้องไม่ขึ้นกับเวลาที่ network ตอบอย่างลับ ๆ: บันทึก acceptedTick และลำดับจริงสำหรับ replay; tie-break แบบ deterministic ที่หมุนสิทธิ์ได้เพื่อลดการได้เปรียบของ agentId ต่ำ

สถานะ request: IDLE → QUEUED → IN_FLIGHT → READY → ACCEPTED/REJECTED; เพิ่ม EXPIRED/CANCELLED สำหรับ request ที่หมดอายุหรือถูกยกเลิก โดย map เข้ากับ Decision Staging เดิม ไม่สร้าง action queue อีกชุด

ระหว่างรอ: ทำขั้นที่อนุมัติไว้ต่อได้เมื่อ precondition ยังจริง; reflex ฉุกเฉินต้องเป็นกติกาที่ประกาศร่วมกันและมี trace; หากไม่มีงานที่ปลอดภัยให้ WAIT การพักรอไม่สวมรอยเป็นคำตอบจาก Astra

## 13. ตัวอย่างข้อมูลและวงจรความเชื่อ

ตัวอย่างต่อไปนี้เป็น proposed payload ภายใน ไม่ใช่ schema ที่ใช้งานได้แล้ว และต้อง map เข้าสัญญาของ PR #1 ก่อน implement

```json
{
  "beliefId": "belief:agent-2:water-7:1",
  "claim": {"subject": "water-7", "predicate": "available", "value": true},
  "sourceKind": "message",
  "sourceAgentId": 1,
  "originEvidenceId": "obs:agent-1:120:water-7",
  "observedTick": 120,
  "receivedTick": 135,
  "expiresAtTick": 180,
  "confidence": 0.65,
  "status": "unverified",
  "evidenceIds": ["message:42"]
}
```

Lifecycle: ข้อมูลรายงานใหม่เป็น unverified; ตรวจเองแล้ว confirmed; เก่าเกินอายุเป็น stale; หลักฐานที่เทียบเวลา/เงื่อนไขเดียวกันขัดกันจึง refuted หากเวลาต่างกันให้สร้าง fact revision ใหม่และเก็บประวัติ ไม่ตีตราผู้ให้ข่าวเป็นคนโกหกจากน้ำหมดภายหลัง

ใช้ originEvidenceId และ claim fingerprint กันข้อมูลวน A → B → C → A ไม่ให้กลายเป็นหลักฐานอิสระสามชิ้น Confidence เป็นค่าประมาณเชิงระบบ ต้องวัด calibration ก่อนอ้างว่าเป็นความน่าจะเป็นที่แม่นยำ

Memory compaction เก็บ: เหตุการณ์สำคัญ บทเรียน เงื่อนไขที่ใช้ได้ ข้อยกเว้น และ evidenceIds; ห้ามสรุป observation ที่ไม่เคยมีให้กลายเป็น fact เก็บหลักฐานขั้นต่ำของบทเรียนที่ยัง active; ถ้าจำเป็นต้องลบให้ระบุ evidenceUnavailable และลดสถานะความเชื่อที่ตรวจย้อนกลับไม่ได้

Retrieval จัดอันดับตาม goal relevance, recency, importance และ evidence quality ภายใต้ token cap; บทเรียนที่เกี่ยวกับความอยู่รอดและคำสัญญาค้างมี priority แต่ต้องมีขอบเขตจำนวนเพื่อไม่ให้ memory โตไม่สิ้นสุด

## 14. World Model และตัวอย่างการเรียนรู้

เริ่มจากโมเดลประมาณการ 3 ชุด ไม่สร้าง universal simulator ซ้อนโลกจริง:

| โมเดล | Input จากความรู้ของ agent | Prediction | Feedback |
| --- | --- | --- | --- |
| เดินทาง | ระยะ/เส้นทางที่รู้ พลังงาน สัมภาระ | เวลาและพลังงานที่ใช้ | เวลา/พลังงานที่ตนใช้จริง |
| ก่อสร้าง | ขนาดทีมที่ตอบรับ ทักษะที่รู้ วัสดุที่เชื่อว่ามี | โอกาส/เวลาทำเสร็จ | ความคืบหน้าที่เห็นและผลการร่วมงาน |
| เตรียมรับพายุ | สัญญาณอากาศ ที่พักที่รู้ เสบียงที่เคยเห็น | ความเสี่ยงขาดแคลน | ความเสียหายและความขาดแคลนที่รับรู้ |

แยก observed association ออกจาก causal claim: ทำนายดีขึ้นไม่ได้พิสูจน์เหตุ–ผลโดยอัตโนมัติ บันทึก context ของแต่ละตัวอย่างและไม่เหมารวมภูมิประเทศ/โหลดต่างกัน

Plan step ต้องมี stepId, actionType, target, preconditions, successCondition, timeoutTick และ onFailure โดย onFailure ใช้ enum ที่ runtime รู้จัก เช่น REPLAN/RETRY_BOUNDED/ABORT ไม่รับโค้ด executable จาก provider

ตัวอย่าง: A คาดว่าจะขนน้ำกลับทันค่ำ แต่สัมภาระหนักทำให้ช้ากว่าที่คาด → บันทึก error → ปรับเวลาประมาณการสำหรับโหลดใกล้เคียง → รอบถัดไปออกเร็วขึ้นหรือขอ B ช่วยขน การเรียนรู้ต้องเห็นในการเปลี่ยนแผนและผลจริง

## 15. กลไกความร่วมมือที่ไม่กำหนดบทบาทล่วงหน้า

TeamTask มี taskId, proposerId, objective, location, requiredParticipants, materialNeeds, startWindow, deadlineTick, memberCommitments และ completionEvidence สมาชิกเลือก ACCEPT/DECLINE เอง Coordinator เปลี่ยนได้เมื่อสมาชิกยอมรับ

สถานะงาน: PROPOSED → RECRUITING → READY → IN_PROGRESS → COMPLETED; ทางออก FAILED/CANCELLED/EXPIRED มีเหตุผลและการคืน reservation ที่ยังไม่ใช้

Commitment ไม่เท่ากับกระทำจริง: นัดว่าจะมาช่วยไม่เพิ่ม XP หรือชื่อเสียงจนมี contribution ที่ resolver ยืนยัน; ประเมินผิดนัดแยกจากเหตุสุดวิสัยที่สมาชิกได้รับหลักฐาน ห้ามสร้าง trust เพิ่มด้วยข้อความ OFFER วนซ้ำ

ข้อจำกัดโลกที่ทำให้การร่วมมือมีประโยชน์: ช่วงเวลาก่อนพายุสั้นกว่างานทั้งหมดที่คนเดียวทำไหว, วัสดุอยู่คนละบริเวณ, ผู้บาดเจ็บทำงานได้น้อยลง และงานก่อสร้างต้องมีสองคนตามกติกาเดิม ปรับค่าบน tuning seeds แล้วล็อกก่อนประเมิน ไม่บังคับแพ้ด้วยโบนัสลับให้ทีม

## 16. Provider isolation, scheduling และงบ

- Bridge ผูก session ฝั่ง server กับ simulationId/runEpoch/agentId ไม่เชื่อ identity ที่ client เปลี่ยนเอง; credential ไม่อยู่ใน HTML หรือ save ที่แจกผู้เล่น
- Shared model weights/connection pool ได้ แต่ shared conversation history ไม่ได้; request context สร้างจากข้อมูลเฉพาะคนเท่านั้น
- จำกัดหนึ่ง active decision ต่อคนในรุ่นแรก; replan ใหม่ยกเลิก request เดิมเชิงตรรกะ แม้ network cancel ไม่สำเร็จก็ไม่รับผลเก่า
- Priority ใช้ urgency, invalidatedPlan และ waitingAge; ตั้ง maxWaitTicks และรายงานการเกินงบจริง ไม่รับรอง SLA ที่ provider ทำไม่ได้
- Queue cap, concurrency cap, tokens/call, tokens/minute, calls/minute และ retry cap เป็น config แยก; 429 ใช้ retry ที่มี jitter และเพดาน; งบหมดหยุดส่งเพิ่ม
- Cache ใช้ได้เฉพาะผลที่ไม่ทำให้ความรู้ข้ามคน ไม่แชร์คำตอบที่ผูกกับ memory ของอีกคน
- เก็บ provider/model identifier ที่ระบบตอบจริงเมื่อมี พร้อม mode และ fallbackReason; ชื่อ endpoint หรือป้าย UI อย่างเดียวไม่พอพิสูจน์ว่าใช้ Astra

ตัวอย่างงบเชิงสมมติ: 100 คน คิดเฉลี่ยคนละ 0.5 ครั้ง/นาที ที่ 1,200 input และ 200 output tokens = 50 calls และประมาณ 70,000 tokens/นาที ก่อน retries จึงต้องวัดอัตราคิดจากเกมจริงก่อนเพิ่มประชากร ตัวเลขนี้ไม่ใช่ราคาและไม่ใช่ quota ที่มีอยู่

## 17. Persistence, migration และ rollback

Save envelope: saveSchemaVersion, simulationId, runEpoch, tick, seed, rngState, worldState, agentPersistentStates, pendingCommitments และ eventLogCursor; เก็บ provider responses ใน replay log แยกจาก credential

Migration ทำสำเนา input แล้วตรวจ schema ก่อนคืนผล: facts Map → serializable entries; legacy text memory → episode ชนิด legacy โดยไม่แต่ง evidence; ข้อมูลไม่มีเวลา/ต้นทางต้อง marked unknown; ห้ามแปลง legacy text เป็น confirmed fact อัตโนมัติ

Restore เพิ่ม runEpoch เพื่อไม่รับ response ที่ค้างจากก่อน restore; ยกเลิก network requests เดิมและสร้าง request ใหม่เมื่อต้องคิด โดยเก็บความทรงจำเดิมและป้องกัน actionId ซ้ำ มี reset กับ resume คนละเส้นทาง

Release ทุกชุดแนบ schema compatibility table และ snapshot fixture ก่อน/หลัง migration; ถ้า rollback ไม่รองรับ save ใหม่ ให้กลับไป checkpoint ก่อน migration ไม่โหลด schema ใหม่ด้วยโค้ดเก่าแบบเงียบ ๆ

## 18. Acceptance matrix สำหรับ implementation

ตารางนี้เป็นแผนทดสอบ ยังไม่มีแถวใดอ้างว่ารันผ่านใน PR เอกสารนี้

| ID | การทดลอง | เกณฑ์ผ่าน | ระยะ |
| --- | --- | --- | --- |
| OBS-01 | เปลี่ยนน้ำนอกสายตาโดย observation ของ B คงเดิม | request ของ B คงเดิมเมื่อเวลา/RNG คงเดิม | Memory |
| OBS-02 | A ส่งข่าวถึง B แต่ไม่ถึง C | B ได้ unverified belief; C ไม่ได้ข้อมูล | Memory |
| BEL-01 | ส่งข่าวต้นทางเดียววนหลายคน | จำนวนหลักฐานอิสระไม่เพิ่ม | Memory |
| BEL-02 | น้ำหมดหลังผู้รายงานเห็นจริง | fact stale/updated ไม่ลงโทษเป็นข่าวเท็จทันที | Memory |
| MEM-01 | เกิน memory cap แล้วเรียกบทเรียนสำคัญ | ดึง lesson พร้อม provenance หรือสถานะหลักฐานหายได้ | Memory |
| WM-01 | เปลี่ยนโหลดการเดินทาง | prediction error และการปรับแผนถูกบันทึก | Prediction |
| PLAN-01 | เป้าหมายหายกลางแผน | เลิกขั้นที่ใช้ไม่ได้ภายใน replan budget ที่ตั้งไว้ | Planning |
| TEAM-01 | สมาชิกตอบรับแล้วถอนตัว | ทีมปรับสมาชิก/ยกเลิก ไม่ค้าง reservation | Cooperation |
| ACT-01 | สองคนใช้ทรัพยากรชิ้นสุดท้าย | ไม่มี stock ติดลบและไม่สำเร็จสองครั้ง | Core |
| API-01 | ส่ง response อีก agent/session | reject โดยไม่มี state ปะปน | Provider |
| API-02 | ส่งซ้ำและส่งหลัง reset | ผลโลกเกิดได้ไม่เกินหนึ่งครั้ง; epoch เก่าถูกปฏิเสธ | Provider |
| API-03 | timeout/429/งบหมด | คุมจำนวน retry; mode/fallback ตรง trace | Provider |
| SAVE-01 | save → load → เดินต่อ | identity, skill, belief, commitment คงอยู่ตาม schema | Persistence |
| REPLAY-01 | replay จาก recorded decisions | state hash ตรงที่ checkpoint ที่กำหนด | Persistence |
| REG-01 | รัน gate เดิม 60 agents/1000 ticks | integrity ผ่าน; รายงาน emergent roles และความสามารถเดิม | ทุก runtime PR |

เริ่ม unit/contract cases ที่เฉพาะเจาะจงก่อน integration scenario; ไม่เพิ่ม test ที่ตรวจเพียงว่า implementation เรียก function ของตัวเอง ตัว acceptance harness ของ PR #1 ต้องอ่านและรันจริงก่อนใช้เป็น gate ของ release

## 19. แผนทดลองและนิยาม metric

Evaluation รุ่นแรกเสนอ 20 agents, 10 simulated days, tuning seeds 5 ชุด และ held-out seeds 20 ชุด ล็อก dayTicks, scenarioVersion, provider settings และ resource budget ก่อนเริ่ม รอบที่ crash ต้องนับและรายงาน ห้ามทิ้งรอบแย่เพื่อทำค่าเฉลี่ยสวย

ทดลอง paired seeds ระหว่าง full system กับ no-communication, no-learning และ no-prediction โดยปิดองค์ประกอบครั้งละหนึ่งตัว คงความสามารถกระทำและเพดานงบเดียวกัน บันทึกงบที่ใช้จริง; หาก provider stochastic ให้มีหลาย run ต่อ seed หรือแสดงข้อจำกัดของตัวอย่างอย่างชัดเจน

- Survival rate = alive at evaluation end / initial population; ปิดการเพิ่มประชากรระหว่าง benchmark
- Cooperation completion = completed joint tasks / accepted joint tasks ที่ deadline ถึงแล้ว; แสดง pending แยกเพื่อกันตัวหารผิด
- Repeated failure = failure ที่ action/target/context เดิมซ้ำในหน้าต่างที่กำหนด แยก transient network failures
- Prediction error = absolute error สำหรับเวลา/พลังงาน; binary success ใช้ Brier score เมื่อมี probabilistic prediction ที่นิยามแล้ว
- Resource deprivation = agent-ticks ที่เกิน hunger/thirst threshold / total alive agent-ticks
- Fairness = p95 และ max decision wait พร้อมจำนวนคนที่ไม่ได้รับ decision ภายใน budget

เป้ารับรองที่เสนอสำหรับ cooperation: survival gain เฉลี่ยอย่างน้อย 10 percentage points และ paired 95% confidence interval อยู่เหนือศูนย์บน held-out set; เป็นเป้าทดลอง ไม่ใช่ผลที่ได้แล้ว หากไม่ผ่านให้รายงานและหาสาเหตุ ไม่ลดเกณฑ์ย้อนหลัง Prediction ต้องดีขึ้นบนข้อมูลประเมินที่กันไว้เทียบกับ frozen baseline โดยรายงานขนาดผลและจำนวนตัวอย่าง

## 20. แบ่งงานเป็น PR ที่ตรวจได้

| ลำดับ | Deliverable | Dependency | เกณฑ์จบ |
| --- | --- | --- | --- |
| P0 | ทบทวนและรวม core hardening PR #1 | V0.5 | รัน core acceptance จริงและแก้ข้อพบ |
| P1 | Knowledge boundary + structured belief | P0 | OBS-01/02, BEL-01/02 และ regression |
| P2 | Memory compaction + migration + Inspector | P1 | MEM-01, SAVE-01 และ fixture |
| P3 | Predictions + outcome comparison | P2 | WM-01 และรายงาน error |
| P4 | Executable plans + bounded replanning | P3 | PLAN-01 และ stuck cases |
| P5 | Team commitments + cooperation scenarios | P4 | TEAM-01, ACT-01 และ ablation เบื้องต้น |
| P6 | Real provider bridge + isolation | P2; integration กับ P4/P5 | API-01/02/03; ยืนยันช่องทาง provider จริง |
| P7 | Scheduler scale + persistence/replay | P5/P6 | SAVE-01, REPLAY-01 และ profiling |
| P8 | V1.0 benchmark/report | P7 | held-out evaluations และ replay ตัวอย่าง |

P6 เริ่มตรวจความพร้อม provider ได้ตั้งแต่หลัง P0 เพื่อค้น blocker เร็ว แต่ห้ามเรียกผ่าน context ที่ยังไม่ผ่าน knowledge boundary งานแต่ละ PR ต้องมี scope, migration impact, test evidence และข้อจำกัดจริง ใช้แผนนี้เป็น backlog ต่อเนื่องโดยไม่เปิด PR implementation ทั้งหมดพร้อมกัน

## 21. Definition of Done และประเด็นที่ต้องตัดสินจากหลักฐาน

- ทุก runtime PR ต้องอ้าง base commit ล่าสุดหลัง dependency รวมแล้ว มี diff เฉพาะงาน และไม่มี prototype override ซ้อนที่ทำให้เส้นทางใหม่ถูกทับ
- Export ที่รองรับต้องมี restore test; provider mock ผ่านไม่เท่ากับ real provider gate ผ่าน; build ผ่านไม่เท่ากับ survival benchmark ผ่าน
- Inspector แสดง observed facts, reported beliefs, current goal, next action, prediction/outcome และเหตุผลสรุปที่ระบบบันทึก ไม่อ้างว่าเปิดเผยความคิดภายในทั้งหมดของโมเดล
- จำกัดการเพิ่ม UI ให้อ่านได้บนมือถือ: เลือกหนึ่งคนแล้วสลับแท็บ ความรู้/แผน/สังคม/ผลลัพธ์ รายละเอียด developer trace พับเก็บ
- เลือก Worker หรือ backend หลังวัดภาระจริง; หากต้องให้โลกดำเนินต่อเมื่อปิดหน้า HTML ให้ backend เป็น runtime authority ส่วนหน้าเว็บเป็น client
- ค่าจำนวนคน cadence การคิด timeout และต้นทุนเป็น configuration พร้อม benchmark ห้าม hardcode ตามตัวเลขตัวอย่างในแผนโดยไม่วัด
- ความเสี่ยงหลัก: provider unavailable, token budget, hidden-state leakage, ข่าววน, survival tuning และ save compatibility มี gate แยกตามตารางข้างต้น

ผลลัพธ์แรกที่ต้องส่งให้ผู้ใช้ทดลองยังคงเรียบง่าย: เปิดโลก เลือก A กับ B แล้วเห็นว่าทั้งคู่รู้ต่างกัน ข่าวเดินทางอย่างไร และหลักฐานใดทำให้แต่ละคนเปลี่ยนแผน จากนั้นจึงพิสูจน์การร่วมมือและขยายจำนวนมนุษย์
