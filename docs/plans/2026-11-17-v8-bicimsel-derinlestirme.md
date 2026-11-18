# V8 Biçimsel doğrulamayı derinleştirme — Uygulama planı

**Goal:** `docs/specs/V8.md`'deki AC-V8-01..13'ü karşılamak. Bu plan şunları kurar:
- kapsam denetimi;
- eskime denetimi ve `formal verified`;
- `architecture/formal/` için ince `guard` ve R2 tabanı;
- `plan check`'te kayıt `touches` kuralı;
- `formal trace`, `states tests` ve iki drift öğesi;
- `proof_check`;
- skill'ler ve uçtan uca test.

**Architecture:**
- Yeni mantık yeni dosyada: `src/lib/formalmaint.sh`:
  - kapsam denetimi;
  - eskime kümesi ve eskime;
  - `formal verified`;
  - `formal trace`;
  - `states tests`;
  - CE ve ST kimlik listeleri.
- `formal.sh` (615 satır) yalnızca çağrılar alır:
  - `sw_formal_record_problems` ya da `sw_formal_check_one` kapsam ve eskime denetimini çağırır;
  - `sw_formal` yeni alt komutları yönlendirir.
- Var olan dosyalarda küçük ekler:
  - `guard.sh`: `architecture/formal/` `SW_PROTECTED`'den çıkar, yerine ince kural gelir; `architecture/proofs/` eklenir.
  - `risk.sh`: R2 tabanı.
  - `plan.sh`: kayıt `touches` kuralı.
  - `drift.sh`: `untested` ve `unreplayed`.
  - `verify.sh` ve `doctor.sh`: `proof_check`.
  - `src/bin/softwary`: `help`, `states`.
- Var olan yardımcılar yeniden kullanılır:
  - TLC çağrısı ve yol basımı (`sw_formal_tlc`, `sw_formal_cfg`, `sw_formal_trace`);
  - tablo okuma (`sw_formal_table`, `sw_formal_findings`);
  - `guard`'ın taban çözümü (ortak ata, D-84) ve `touches` eşleşmesi (`sw_guard_covers`);
  - drift'in `test_paths` taraması (`sw_drift_unexercised`'ın yöntemi);
  - `model_check` zorunluluk kuralı (`proof_check` için örnek).

**Tech Stack:** POSIX `sh`, `git`, `jq`, Java 21 ve `tla2tools.jar` (testlerde gerçek TLC; `tests/tlc.sh`), `shellcheck`.

**Spec:** `docs/specs/V8.md` (approved). Bağlam:
- `docs/design.md` §4, §5, §7 (biçimsel doğrulama: kurallar, sürekli, sınır);
- `docs/sources.md` §5 (pstack maddeleri 3, 4, 5, 8 ve 9);
- `docs/decisions.md`:
  - D-63;
  - D-84..D-87 (`guard`);
  - D-117..D-123 ve D-133 (kayıt, `formal check`, onay özeti);
  - D-142, D-143, D-151 (bulgu);
  - D-157..D-159, D-166, D-170 (repro, drift).

## Global Constraints

- Scriptler POSIX `sh`; yeni bağımlılık yok.
- `shellcheck -s sh -x` temiz; çıkış kodları `0/1/2`; paket içeriği İngilizce, `docs/` Türkçe.
- Her test `test_` ile başlar ve üstündeki yorum kriter kimliğini taşır. Önce test yazılır, kırmızı görülür ve kırmızı koşunun çıktısı commit mesajına bir satırla not edilir (`red: <test> FAIL`); sonra kod.
- Paket içeriği ve fikstür stack'e özgü sözcük denetiminden geçer (AC-M0-09).
- Kararlar `docs/decisions.md`'ye "## V8" başlığı altında D-176'dan başlayarak yazılır; sapmalar kendi satırına.
- Dal `claude/zen-ramanujan-jy9sc6`; push ve PR'ı orkestratör yapar.
- Değişmez cümleleri ve `## Findings` hiçbir komutla yazılmaz: `formal verified` yalnızca `## Last verified` satırını değiştirir.

## Kararlar (decisions.md'ye girer)

- **D-176 Spec onayı:** V8 spec'i kullanıcı isteğiyle yazıldığı oturumda `approved` yapıldı (D-154 gibi).
- **D-177 Modelin döngüde bakımı:** *insan onaylı (2026-11-17): döngü bağlayıcı tablolar dışında modeli değiştirebilir.*
  - `architecture/formal/` `SW_PROTECTED`'den çıkar.
  - `guard` o dizinde şunları korunan sayar:
    - `git diff --name-status` ile `A`, `D` ya da `R` olan dosyayı;
    - `M` olan bir `.md`'de `## Invariants` ya da `## Findings` tablosunun ham satırlarının taban sürümünden farklı olmasını. Karşılaştırma `sw_formal_invariants_raw` ve `sw_formal_findings_raw` ile, iki sürüm `git show` ile geçici dosyaya alınarak yapılır.
  - Satır biçimi öbür korunan yollarla aynıdır.
  - `risk`: `architecture/formal/*` en az R2.
  - `architecture/proofs/` `SW_PROTECTED`'e girer.
- **D-178 Eskime:** *insan onaylı (2026-11-17): eskimiş model `model_check`'te FAIL'dir.*
  - **Eskime kümesi:**
    - kapsanan yollar (`planned` olmayan satırlar);
    - `architecture/formal/<ad>.tla` ve `<ad>*.cfg`;
    - `## Coverage` tablosu.
  - **Yolların karşılaştırması:** `git diff --name-only <C> -- <yollar>`; çalışma ağacı dahildir, izlenmeyen yeni dosya `git ls-files --others` ile eklenir.
  - **Tablonun karşılaştırması:** `## Coverage` ham satırları `git show <C>:<kayıt>`'takiyle karşılaştırılır; fark varsa yol yerine `## Coverage` yazılır.
  - **Kaydın `.md`'si kümeye girmez.** `formal verified`'ın yazdığı satır commit'lenince hüküm bozulmaz, değişmez ve bulgu tabloları da onay özetinde zaten bağlıdır.
  - **Yer:** eskime ve kapsam denetimi `formal check`'in her belirtimi için TLC'den önce çalışır. Sorun varsa satırlar basılır ve TLC yine çalışır, böylece model hatası da görünür. Sonuç başarısızdır.
- **D-179 `formal verified`:**
  - **Sıra:**
    1. ad ve hüküm (2);
    2. kaydedilmemiş değişiklik: eskime kümesinde `git diff --quiet HEAD` ve izlenmeyen dosya;
    3. `formal check <ad>`'in eskime dışı sonucu (iç çağrıda eskime denetimi kapalı);
    4. hüküm tutarlılığı (`.tla` ve `.cfg` `git diff --quiet <C> HEAD`).
  - **Yazım:** `## Last verified` bölümünün ilk boş olmayan satırı `<HEAD sha> <hüküm>` ile değiştirilir; yorumlar ve öbür bölümler korunur. Olay günlüğüne `formal_verified <ad> <hüküm> <sha7>`. Bozuk kayıt 2'dir.
  - **`bug` ve `blocked`:** `formal verified: bug and blocked go to the human (./softwary job escalate <job> <question>)` ve 2.
- **D-180 Kayıt `touches`'ı:** `plan check` her dilimin her `touches` girdisini her belirtimin kapsanan yollarıyla iki yönlü karşılaştırır: girdi yolu kapsıyorsa ya da yol girdiyi. Kapsanan yol `planned` değilse ve kayıt `touches`'ta yoksa sorundur. `done` dilimler denetlenmez.
- **D-181 Kimlikler:**
  - **CE:** `CE-<ad>-<değişmez>`.
  - **ST:** `ST-<varlık>-<durum>-<olay>`. Olaylar, varlığın geçişlerindeki ayrık olay adlarıdır. Durumlar `states` sırasıyla, olaylar ilk görülme sırasıyla basılır. Son durumlardaki çiftler de `refused` yükümlülüğüdür.
  - **Eşleşme:** `test_paths` altındaki izlenen dosyalarda `grep -F` ve ardından sözcük sınırı. Kimliğin hemen ardından gelen karakter harf, rakam, `_` ya da `-` olmamalıdır; `ST-order-paid-ship` `ST-order-paid-shipped`'e eşleşmez.
  - **Drift sırası:** öğeler V7 sırasının sonuna `untested`, sonra `unreplayed` olarak eklenir.
- **D-182 `formal trace`:** İyi model yalnızca o değişmezle çalıştırılır (`sw_formal_cfg ... only`, V6'daki bulgu çalıştırmasının aynısı). Çıktı `CE-...` satırı, ardından `sw_formal_trace` satırlarıdır. TLC yoksa `formal install`'ı söyleyip 2 döner.
- **D-183 `proof_check`:** AC-V5'teki `model_check` kuralının aynısı.
  - Şablonda yorum: `# proof_check = <command that checks architecture/proofs/>`.
  - Gerekme koşulu: `git ls-files 'architecture/proofs/*.lean'` ya da çalışma ağacında bir `.lean` dosyası.
  - `verify` satırı `proof_check`'tir; muaf tutulabilir değildir ve `_files` almaz.
- **D-184 Test düzeneği:**
  - **Gerçek TLC:** `tests/tlc.sh`'in yöntemiyle; Java ya da jar yoksa test V5 testlerinin yaptığını yapar.
  - **Fikstür:** `tests/fixtures/existing/architecture/formal/order.md` `never` taşır ve `app/order.sh`'i kapsar; V8'de o fikstürle `model_check` çalıştıran eski testler artık kırmızı başlar. Düzenek, fikstürü commit'ledikten sonra `formal verified order compatible` çalıştırıp kaydı commit'leyen bir `existing_verified` yardımcısı ekler. Bu yardımcıyı kullanmak zorunda kalan her eski test D-satırında listelenir.
  - **Yeni test dosyaları:** `tests/formal_maint_test.sh`, `tests/formal_guard_test.sh`, `tests/formal_trace_test.sh`, `tests/proof_test.sh`, `tests/formal_e2e_test.sh`.

## Review Focus

1. **Eskime gerçekten hesaplanmalı:** çalışma ağacındaki kaydedilmemiş değişiklik, izlenmeyen yeni kapsanan dosya ve `## Coverage`'a yeni satır eklenmesi eskime sayılmalı. Kaydın `.md`'sinin commit'i saymamalı (T1).
2. **`formal verified` hiçbir ret yolunda dosya yazmamalı.** `compatible` modeli değişmiş bir işte reddedilmeli (T1).
3. **`guard` bağlayıcı tabloyu taban sürümüyle karşılaştırmalı:** ortak ata, D-84; işin kendi sürümü değil. Tablo dışındaki satırların değişmesi korunan sayılmamalı. Yeni `.cfg` ya da `.tla` dosyası korunan sayılmalı (T2).
4. **Kimlik eşleşmesi sözcük sınırlı olmalı;** test dosyası dışındaki dosyalar (`src_paths`) kimliği anıyor diye öğe kapanmamalı (T3).
5. **Eski kayıtlar:**
   - `<sha>` tek başına (V5 biçimi) geçerli kalmalı;
   - `never` + yalnızca `planned` kapsam eskimiş sayılmamalı;
   - blueprint aşamasındaki V5 testleri (kod yok) etkilenmemeli (T1).
6. **`formal check`'in süresi:** belirtim başına birkaç `git` çağrısından fazlası eklenmemeli (T1).

---

### Task 1: Kapsam, eskime ve `formal verified` (AC-V8-01, 02, 03)

**Files:**
- Create: `src/lib/formalmaint.sh`, `tests/formal_maint_test.sh`.
- Modify:
  - `src/lib/formal.sh`: çağrılar, `sw_formal` yönlendirmesi, `Last verified` biçim kuralı (`<sha> compatible|updated`);
  - `src/bin/softwary`: source, `help`;
  - `src/templates/artifacts/formal.md`: yorumda `Last verified` ve hükümler;
  - `tests/lib.sh`: `existing_verified`.

- [ ] `test_ac_v8_01_*`:
  - var olmayan yol;
  - dosyada geçmeyen fonksiyon;
  - sözcük sınırı (`order_pay` `order_payment` ile eşleşmez);
  - `planned` satırı atlanır;
  - `blueprint check` de bildirir.
- [ ] `test_ac_v8_02_*`:
  - `never` + kod → FAIL;
  - `never` + yalnızca `planned` → geçer;
  - bilinmeyen commit;
  - kapsanan dosya commit'lendi, kaydedilmedi ya da yeni ve izlenmiyor → `stale` ve yollar;
  - `.tla` değişti;
  - `## Coverage`'a satır eklendi;
  - yalnızca kaydın `.md`'si değişti → geçer;
  - bare `<sha>` geçerli;
  - `model_check` üzerinden `verify` FAIL.
- [ ] `test_ac_v8_03_*`:
  - temiz `compatible` → satır, olay, 0;
  - kaydedilmemiş değişiklik → 1, dosya aynı;
  - TLC kırmızı → 1, dosya aynı;
  - model değişmişken `compatible` → 1;
  - model değişmemişken `updated` → 1;
  - `never`'dan iki hüküm de;
  - `bug`/`blocked`/bilinmeyen → 2;
  - commit'ten sonra `formal check` geçer.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 2: `guard`, `risk`, `plan check` (AC-V8-04, 05, 06)

**Files:**
- Create: `tests/formal_guard_test.sh`.
- Modify: `src/lib/guard.sh`, `src/lib/risk.sh`, `src/lib/plan.sh`.

- [ ] `test_ac_v8_04_*`:
  - `.tla` değişikliği korunan değil;
  - `## Actions`/`## Coverage`/`## Last verified` değişikliği korunan değil;
  - `## Invariants` cümlesinde tek harf → korunan;
  - `## Findings` tarihi → korunan;
  - yeni `.cfg` → korunan;
  - silinen kayıt → korunan;
  - `architecture/proofs/x.lean` → korunan;
  - iş, dosyayı kendi dalında değiştirip tabloyu geri alınca taban sürümü kullanılır.
- [ ] `test_ac_v8_05_*`: `risk.conf` `default = R1` iken `architecture/formal/order.tla` R2.
- [ ] `test_ac_v8_06_*`:
  - kayıtsız `touches` → sorun satırı;
  - kayıtla temiz;
  - dizin `touches` (`app/`);
  - `planned` kapsam sorun değil;
  - `done` dilim atlanır.
- [ ] Eski `guard` testlerinde `architecture/formal/` korunan yol beklentisi varsa güncellenir; gerekçesi kararda.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 3: `formal trace`, `states tests`, drift öğeleri (AC-V8-07, 08, 09)

**Files:**
- Create: `tests/formal_trace_test.sh`.
- Modify:
  - `src/lib/formalmaint.sh`, `src/lib/drift.sh`;
  - `src/bin/softwary`: `states tests`, `help`;
  - `src/templates/artifacts/drift.md`: yorumda yeni öğeler;
  - `tests/drift_test.sh`, `tests/states_test.sh`.

- [ ] `test_ac_v8_07_*`:
  - bulgulu değişmez → `CE-` satırı ve adımlar, 0;
  - bulgusu olmayan → 2;
  - bilinmeyen ad → 2;
  - artık bozulmayan → 1.
- [ ] `test_ac_v8_08_*`:
  - `order` için 12 satır, `allowed -> <hedef>` ve `refused` doğru;
  - varlık süzgeci;
  - bilinmeyen varlık → 2.
- [ ] `test_ac_v8_09_*`:
  - `untested` ve `unreplayed` görünür;
  - testte anılınca kaybolur;
  - `src_paths`'te anılmak yetmez;
  - sözcük sınırı;
  - `accept` kararıyla `decided`;
  - `ship prepare` kararsız öğeyle 1.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 4: `proof_check` (AC-V8-10)

**Files:**
- Create: `tests/proof_test.sh`.
- Modify: `src/lib/verify.sh`, `src/lib/doctor.sh`, `src/lib/config.sh` (gerekirse), `src/templates/commands.conf`.

- [ ] `test_ac_v8_10_*`:
  - `.lean` yok ve anahtar yok → satır yok;
  - `.lean` var ve anahtar yok, `UNSET` ya da `NONE` → `doctor` FAIL ve `verify` FAIL;
  - ayarlı komut geçer ya da düşer (sahte komut);
  - `proof_check_files` tanınmaz.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 5: Skill'ler, uçtan uca test, belgeler (AC-V8-11, 12, 13)

**Files:**
- Create: `tests/formal_e2e_test.sh`.
- Modify:
  - skill'ler: `src/skills/implement/SKILL.md`, `src/skills/diagnose/SKILL.md`, `src/skills/maintain/SKILL.md`, `src/skills/blueprint/SKILL.md`;
  - ajanlar: `src/agents/implementer.md`, `src/agents/reviewer.md`;
  - testler: `tests/skill_test.sh`, eski testler (D-184);
  - belgeler: `docs/decisions.md`, `docs/roadmap.md`, `docs/sources.md`, `docs/design.md` (§5 ve §7, yalnızca gerekiyorsa), `docs/formal/merge.md` (56. satırdaki "V8'de bakımı otomatikleşir" notu, paketin kendi belirtimi için ne değiştiğiyle).

- [ ] `test_ac_v8_11_*`:
  - `implement` ve `implementer` `formal verified` ile `job escalate`'i anar ve değişmez ile bulguyu değiştirmeyi yasaklar;
  - `diagnose` `formal trace` ve `CE-` anar;
  - `maintain` `untested` ve `unreplayed` anar;
  - `blueprint` `proof_check` ve `architecture/proofs/` anar;
  - `reviewer` model zayıflamasını anar;
  - 80 satır, yalnızca `help` komutları, üç araçta dağıtım.
- [ ] `test_ac_v8_12_*` (V6 fikstürü, gerçek TLC):
  1. `app/order.sh`'e dokunan iş → kapıda `stale` → `formal verified order compatible` ve kayıt commit'i → kapı geçer → birleşir.
  2. `.tla`'ya dokunan iş → `compatible` reddedilir → `updated` → geçer.
  3. `## Invariants`'a dokunan iş → `guard` korunan yol → `gate_fail`.
  4. Kapsanan fonksiyonu silen iş → kapsam denetimi → `gate_fail`.
  5. `drift` `untested ST-order-...` ve `unreplayed CE-order-ShippedWasPaid` gösterir; test dosyası kimlikleri anınca ve kalanlara `accept` kararıyla temizlenir.
- [ ] Bütün suite, `shellcheck` ve mutasyon denetimi: her yeni kural bir kez bozulur ve ilgili test `SW_TEST_ONLY` ile kırmızı görülür; kararlara bir satır.
- [ ] Kararlar ve belgeler:
  - `decisions.md` "## V8": D-176..D-184, sapmalar, değişen eski testler;
  - `roadmap.md` V8 notu;
  - `sources.md` durum hücreleri (biçimsel doğrulama).
- [ ] Commit.

## AC → test eşlemesi

| AC | Test |
| --- | --- |
| AC-V8-01..03 | `formal_maint_test.sh` |
| AC-V8-04..06 | `formal_guard_test.sh` |
| AC-V8-07..09 | `formal_trace_test.sh`, `drift_test.sh` |
| AC-V8-10 | `proof_test.sh` |
| AC-V8-11 | `skill_test.sh` |
| AC-V8-12 | `formal_e2e_test.sh` |
| AC-V8-13 | bütün suite |
