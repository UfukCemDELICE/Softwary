# softwary v2 — Tasarım önerisi (taslak)

status: draft

Bu belge `docs/design.md`'nin yerine geçmesi önerilen v2 tasarımıdır. İnsan onaylayana kadar geçerli tasarım `docs/design.md`'dir. v2, softwary v1'in kapılarını beş kaynaktan alınan fikirlerle birleştirir; kaynaklardan metin ya da kod alınmaz, yalnızca fikir alınır (zazencodes GPL-3.0, softwary MIT). Taslak, bağımsız bir danışman incelemesinden (Fable, 2026-11-15) sonra revize edildi; incelemenin bulguları §11'dedir.

## 1. Amaç

Mühendis yapmak istediği ürünü anlatır. softwary:

1. doğru soruları sorarak ürünü onunla birlikte tanımlar,
2. ürünün blueprint'ini çıkarır: bileşenler, veri modeli, akışlar (sequence), durum makineleri, sözleşmeler, kararlar,
3. blueprint'i birbirini engellemeyen iş bloklarına böler,
4. blokları git worktree'lerinde, test önce, paralel yürüten bir döngü başlatır,
5. her bloğu kapılardan ve bağımsız incelemeden geçirip birleştirir ya da insana escalate eder,
6. bunu teslim, işletim ve bakım dahil bütün SDLC boyunca sürdürür.

İnsan ürün tanımını ve blueprint'i onaylar; gerisi akar. İnsan, escalate edilen işlerde, drift kararında ve üretime dağıtımda devreye girer.

Hedef dışı: kendi sunucusu ya da daemon'u olan bir çalışma zamanı, stack adaptörü, issue tracker'a bağımlılık, regülasyon uyumu.

## 2. Kaynaklar ve alınan fikirler

| Kaynak | Alınan fikir | v2'deki yeri |
| --- | --- | --- |
| softwary v1 | Script kapıları (`verify`, `trace`, `adr`, `changes`), CALM modeli kaynak, `sync` ile araç dağıtımı, `commands.conf` sözleşmesi, kriterden teste izlenebilirlik | Çekirdek |
| zazencodes factory v2 | Orkestratör yalnızca koordine eder; durumu yalnızca bir script yazar ve geçersiz geçişi reddeder; her ajan tek dosya yazar, tek satır yanıt verir; inceleyiciler kapıdan geçmemiş işi görmez; kapı ana daldaki denetimlerle çalışır; korunan yollar; riske göre inceleyici seçimi; approver birleştirir ya da somut bir soruyla escalate eder; birleştirmeden önce eşitleme ve yeniden kapı; durum dosyalarda, oturum ölürse devam | Döngü (§6.4) |
| mattpocock/skills | Bütün dallar çözülene kadar sorgulama; sözlük ve kararların görüşmede güncellenmesi; alan modelleme; engelleme ilişkili "tracer bullet" iş blokları; oturum devri | Tanım, blueprint, planlama |
| obra/superpowers | Temiz test tabanıyla worktree; dosya yolları ve doğrulama adımları olan plan; görev başına taze subagent; bitirmeden önce doğrulama; sistematik hata ayıklama | Planlama, uygulama, işletim |
| addyosmani/agent-skills | Yaşam döngüsü evreleri; kalite çıtası ve kapıyı oyunlamaya karşı önlem; taze bağlamda karşıt görüşlü inceleme; "bahane tabloları"; teslimde gözlemlenebilirlik, kademeli yayın, geri alma planı | İlkeler, inceleme, teslim |
| cursor/plugins pstack | İlkeleri küçük, birleştirilebilir dosyalar olarak tutmak; yalnızca kanıtlanan bulguların kaldığı inceleme; etki alanı analizi; durum makineleri ve biçimsel doğrulama; "çalıştığını kanıtla"; geri alınabilir işte insanı bekleme | İnceleme, blueprint, biçimsel doğrulama |

## 3. İlkeler

1. **Talimat değil kapı.** Kritik her kural bir script kontrolüyle uygulanır.
2. **Tek kaynak, üretilen kopyalar.** Araca özel dosyalar ve diyagramlar yapısal kaynaklardan üretilir, elle yazılmaz.
3. **Sözleşme pakette, karşılığı projede.**
4. **Yapılandırılmamış olan başarısızdır; bilinen borç süreli muafiyettir.** Hiçbir kontrol sessizce geçmez. Mevcut bir repoda kırmızı başlayan bir kontrol, gerekçesi ve bitiş tarihi olan bir muafiyetle (`waiver`) sarı gösterilir; süresi dolunca yeniden kırmızıdır. *(değişti)*
5. **Blueprint önce.** Ürün tanımı ve blueprint'in bağlayıcı kısımları insan onayı alır; onlardan sapma insana escalate edilir. *(değişti: "Model önce")*
6. **Yazan incelemez; kanıt kayıtla değil hesapla.** İnceleme temiz bağlamlı ayrı bir ajanla yapılır. Birleştirme scripti hiçbir kayıtlı PASS'e güvenmez; kapıyı birleştirilecek SHA üzerinde kendisi çalıştırır.
7. **Kısa ve yapısal yapıtlar.**
8. **Aşamalı bağlam.**
9. **Durum dosyalarda, geçişler tablodan.** Orkestratör yapıt yazmaz ve durumu doğrudan değiştirmez. Geçişleri `transitions.json` tablosunu uygulayan bir script yapar; her olay ekleme yapılan bir olay günlüğüne yazılır. Oturum ölürse dosyalardan devam edilir. *(yeni)*
10. **Geri alınabilir işte bekleme, geri alınamazda dur.** Döngü insanı yalnızca onay noktalarında, escalate'te ve geri alınamaz eylemlerde bekler. Varsayılan dala birleştirme dağıtım tetikleyebileceği için geri alınamaz sayılır: döngü bir entegrasyon dalına birleştirir. *(yeni)*

## 4. İnsan denetimi ve güven sınırı

İnsanın devredilemez kararları: **ürün tanımı onayı, blueprint onayı, escalate edilen işler, entegrasyon dalının varsayılan dala alınması, drift kararı, üretime dağıtım.**

**Onaylar metin alanı değildir.** `./softwary approve product|blueprint`, onaylanan dosyaların içerik özetlerini kaydeder. Birleştirme ve planlama scriptleri özet uyuşmazsa reddeder. Aynı işletim sistemi kullanıcısı altında bu değiştirilemez değil, yalnızca değiştirildiği anlaşılır bir korumadır (tamper-evident). Daha güçlü sınır için seçenekler §10'dadır.

**Birleştirme kararı approver ajanınındır**, ama approver yalnızca birleştirme scriptini çağırabilir. Script şunları kendisi hesaplar ve biri tutmazsa reddedip işi insana gönderir:

- iş, entegrasyon dalıyla eşitlendikten sonra o SHA üzerinde kapı yeşil,
- diff, dilimin `touches` alanıyla bildirdiği yolların içinde,
- test silinmemiş, atlanmamış (`skip`, `only`), kriter kimliği kaldırılmamış,
- korunan yollara dokunulmamış: `.softwary/`, CI, `CODEOWNERS`, `PRODUCT.md`, blueprint'in bağlayıcı kısımları,
- risk kademesi R3 değil (R3 her zaman escalate),
- tur ve bütçe sınırı aşılmamış.

Her birleştirme gerekçesiyle `decision.md`'ye ve olay günlüğüne yazılır.

## 5. Yapıtlar

| Yapıt | Yol | Onay |
| --- | --- | --- |
| Ürün tanımı | `product/PRODUCT.md`: problem, kullanıcılar, kapsam ve dışı, özellikler, her özellik için kimlikli kabul örnekleri (`EX-<özellik>-NN`), işlevsel olmayan gereksinimler, kısıtlar, başarı ölçütleri | İnsan (`approve product`) |
| Sözlük | `CONTEXT.md` | Görüşmede güncellenir |
| Blueprint, bağlayıcı | `architecture/model/system.calm.json` (bileşenler, ilişkiler), `architecture/data/model.json` (varlıklar, alanlar, ilişkiler), `architecture/contracts/` (OpenAPI) | İnsan (`approve blueprint`) |
| Blueprint, bilgilendirici | `architecture/flows/*.json` (çok bileşenli akışlar), `architecture/states/*.json` (durumlu varlıklar); Mermaid görünümleri `views` ile üretilir | Yok; döngü güncelleyebilir |
| Karar (ADR) | `architecture/decisions/NNNN-ad.md` | Bağlayıcı kısmı değiştirirse insan |
| Spec | `specs/NNN-ad/spec.md`: kabul kriterleri `PRODUCT.md`'deki örneklere bağlanır | Otomatik (§6.3) |
| Dilim | `specs/NNN-ad/slices/Sx.md`: `depends_on`, `touches` | Yok |
| İnceleme | `specs/NNN-ad/reviews/Sx.md` | Yok |
| İş durumu ve olay günlüğü | Ana checkout'ta `.softwary/state/jobs/<iş>/` ve `.softwary/state/events.log` | Yok |
| Muafiyetler | `.softwary/config/waivers.conf`: `anahtar = bitiş-tarihi: gerekçe` | İnsan |

## 6. Hat

### 6.1 Tanım (`define`)

Ürünün her dalı çözülene kadar tek tek soru sorulur; sözlük görüşmede güncellenir. Çıktı `PRODUCT.md`. Her özellik, insanın onaylayacağı somut kabul örnekleri taşır: niyetin test edilebilir hale geldiği yer burasıdır. Kapı: `./softwary product check` (zorunlu bölümler, açık soru yok, her özelliğin örneği var) ve `approve product`.

### 6.2 Blueprint (`blueprint`)

Onaylı üründen bileşen modeli, veri modeli, sözleşmeler; yalnızca birden çok bileşene dokunan akışlar için akış tanımı; durumlu varlıklar için durum makinesi; ADR'ler. Taze bağlamlı bir eleştirmen blueprint'i kırmaya çalışır. Kapı: `./softwary blueprint check` (her özelliğin bir bileşene ve gerekiyorsa bir akışa bağlanması, akışların var olan bileşen ve varlıklara başvurması, modellerin geçerliliği) ve `approve blueprint`.

### 6.3 Planlama (`plan`)

Blueprint özellik başına spec'e, spec dilimlere bölünür. Her spec kriteri `PRODUCT.md`'deki bir kabul örneğine bağlanır. Taze bağlamlı `spec-analyst` her spec'i denetler. `trace` ve analist PASS ise planlama scripti spec'i `approved` yapar; ürün ya da bağlayıcı blueprint değişikliği gerektiren spec escalate edilir. Kapı: `trace`, bağımlılık grafiği döngüsüz.

### 6.4 Döngü (`run`)

Tek bir orkestratör oturumu (Claude Code'da bir skill) kuyruğu boşaltır. Bir dilim, `depends_on`'u birleşmiş ve `touches`'ı çalışan işlerle ve ortak dosyalarla (kilit dosyaları, migration'lar, `CONTEXT.md`, üretilen dosyalar) kesişmiyorsa başlar; en fazla `concurrency` iş aynı anda.

Her iş: kendi worktree'si, dalı ve bağımlılık hazırlığı (`bootstrap`) → `implementer` (test önce, `verify --fast`) → kapı (ana daldaki denetimlerle tam `verify`) → inceleyici (kanıtlı bulgular) → `approver` → birleştirme kuyruğu. Birleştirmeler tek tek yapılır: eşitle, o SHA üzerinde kapı, entegrasyon dalına birleştir. Entegrasyon dalı kırmızıya dönerse hat durur ve son birleştirme geri alınır.

Sınırlar ve gözlem:
- iş başına `max_rounds`, iş başına ve koşu başına süre ve maliyet bütçesi,
- kararsız testler için kural: bir kez yeniden çalıştır; yine kararsızsa işi durdur ve insana bildir, testi asla gevşetme,
- `./softwary status`: işler, aşamalar, süreler ve escalate kutusu; bir iş insanı beklerken diğerleri sürer.

İş durum makinesi küçük olduğu için TLA+ ile değil, `transitions.json` üzerinden her durum × olay çiftini deneyen kapsamlı testlerle doğrulanır. Paralel birleştirme protokolü (çöküşler dahil) TLA+ ile belirtilir.

### 6.5 Teslim ve işletim

`ship`: entegrasyon dalını varsayılan dala alma önerisi, sürüm notu, gözlemlenebilirlik, kademeli yayın ve geri alma planı; dağıtım insan onayıyla. `diagnose`: önce hatayı yeniden üreten test. `maintain`: drift denetimi.

## 7. Güven, değerlendirme ve biçimsel doğrulama

- **Değerlendirme (eval).** Approver'a güvenmek kanıt ister. Bilinçli olarak bozuk diff'ler içeren bir örnek repo ile yakalama oranı ölçülür; döngü varsayılan olarak ancak bu ölçüm belirlenen eşiği geçtiyse kendi kendine birleştirir.
- **Ajan izinleri.** Arka plan ajanlarının ağ, `gh` ve gizli bilgi erişimi kısıtlanır; yalnızca kendi dalına push eder.
- **Biçimsel doğrulama.** TLA+ paketin kendi paralel birleştirme protokolü için kullanılır (değişmezler: kapısı yeşil olmayan SHA entegrasyona girmez; `touches`'ı kesişen iki iş aynı anda çalışmaz; iki adım arasındaki çöküş kurtarılabilir; her iş bir son duruma ya da insana ulaşır). TLC Java gerektirir; yalnızca paketin geliştirme bağımlılığıdır. Projeler için isteğe bağlı `model_check` anahtarı yalnızca "yapılandırılmış denetleyici `architecture/formal/` belirtimlerinden geçti" der; kodun belirtime uyduğunu iddia etmez. Ajanın yazdığı değişmezler blueprint onayında insana düz dille gösterilir. Lean kullanılmaz; Alloy veri modeli kısıtları için isteğe bağlıdır.

## 8. Araçlar ve uygulama dili

Önce Claude Code, sonra Cursor. Kapılar ve `job`, `queue`, `merge` scriptleri POSIX `sh` ve `jq` ile, dosyalar üzerinde saf fonksiyonlar olarak kalır; kilitler `mkdir` ile (Git Bash'te `flock` yok). Durum kodu gerçek eşzamanlılık ilkelleri gerektirir ya da yaklaşık 500 satırı geçerse dil yeniden düşünülür.

## 9. v1'den değişenler

- Spec onayı insandan alınıp `PRODUCT.md` örneklerine bağlı otomatik onaya geçti.
- Birleştirme approver'a geçti, ama hedef entegrasyon dalıdır; varsayılan dala alma ve dağıtım insanda.
- Taban çizgisi, süreli muafiyet anlamına geldi.
- Yol haritasındaki M4a ("döngü onay vermez ve birleştirme yapmaz"), M4b ("worktree'leri kullanıcı açar") ve D-44 v2 ile geçersiz olur.

## 10. Yol haritası önerisi

| No | Kilometre taşı | Teslim |
| --- | --- | --- |
| V1 | Deneme düzeltmeleri | Varsayılan dalın algılanması, skill'lerde `--fast`, dürüst `doctor`, tek geliştirici modu, süreli muafiyetler, boş repo yolu |
| V2 | Yürüyen iskelet | Boş bir oyuncak repoda uçtan uca: ince `define` ve `approve product`; ince blueprint (CALM ve veri modeli) ve `approve blueprint`; `depends_on`'lu plan; sıralı döngü (`job` scripti, `transitions.json`, olay günlüğü, kapı, bir inceleyici, entegrasyon dalına birleştiren approver, bütçe ve `max_rounds`). Gösterim: küçük bir API'yi anlat, iki kez onayla, birleşmiş ve test edilmiş dilimleri al. |
| V3 | Güveni sertleştirme | Korunan yollar, diff ⊆ `touches`, test gevşetme denetimleri, R3 escalate, bozuk diff'lerle değerlendirme |
| V4 | Paralel | Worktree'ler, kilitler, birleştirme kuyruğu, çöküşten devam, birleştirme protokolünün TLA+ belirtimi |
| V5 | Tanım ve blueprint'i derinleştirme | Sorgulama, akışlar, durum makineleri, eleştirmen; döngünün takıldığı yerlere göre |
| V6 | Mevcut repo | Next.js deneme reposunda yeniden |
| V7 | Teslim ve işletim | `ship`, `diagnose`, drift |
| V8 | Proje biçimsel doğrulaması | `model_check` |
| V9 | Cursor ve sürüm | Cursor orkestratörü, kurulum kanalları, `v0.1.0` |

Her kilometre taşından sonra gerçek bir projede deneme yapılır.

## 11. Danışman incelemesi ve insanın karar vereceği sorular

Fable incelemesinin bu taslağa işlenen başlıca bulguları: onayların metin alanı olarak taklit edilebilmesi; kayıtlı PASS'e güvenilmesi; R3'ün zayıflaması; test gevşetmenin kapısız kalması; varsayılan dala birleştirmenin dağıtım tetikleyebilmesi; `touches`'ın doğrulanmaması; birleştirme kuyruğu, kararsız test, bütçe ve geri alma kurallarının eksikliği; elle yazılan Mermaid'in ilke 2'yi tersine çevirmesi; iş durum makinesi için TLA+'ın gereksiz törene dönüşmesi; yol haritasının döngüden önce üç belge kilometre taşı koyması.

İnsanın karar vereceği sorular:

1. Approver doğrudan varsayılan dala mı birleştirir, yoksa entegrasyon dalına mı (sonra insan alır)? Varsayılan dal otomatik dağıtım yapıyor mu?
2. Onay güven sınırı: değiştirildiği anlaşılır içerik özetleri yeterli mi, yoksa süreç dışı bir sınır mı (imzalı etiket ya da ajanlar için ayrı bir GitHub bot kimliği)?
3. İlk hedef: döngü çalışana kadar yalnızca boş repo mu, yoksa mevcut repo da paralel mi?
4. GitHub PR ve CI döngüde ikinci kapı olarak zorunlu mu, yoksa birleştirmeler yalnızca yerel mi?
5. Sert sınırlar: R3 ve korunan yol değişiklikleri her zaman escalate edilsin mi; iş ve koşu başına varsayılan bütçe ne olsun?
