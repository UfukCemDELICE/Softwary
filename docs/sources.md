# Kaynaklar

softwary v2, beş kaynağın fikir sentezidir (D-49). Bu belge her kaynaktan ne alındığını, neyin bilerek alınmadığını ve bunların softwary'de nerede durduğunu kalıcı olarak kaydeder. Bir ajanın ya da insanın kaynakları yeniden okumadan yönü bulabilmesi için yazılmıştır. Kaynak yorumu bir oturumun belleğinde değil, burada durur.

Kurallar:

- Kaynaklardan yalnızca fikir alınır; metin ya da kod alınmaz (zazencodes GPL-3.0, softwary MIT).
- Bir kaynağın rolü, insanın onu neden verdiği ile birlikte yazılır. Rolü yanlış okumak, örneğin bir yaklaşım örneğini paketleme hedefi sanmak, yanlış bir yol haritasına götürür.
- Bir fikrin durumu değiştiğinde (uygulandı, ertelendi, bırakıldı) bu belge aynı değişiklikte güncellenir.

Okuma: 2026-11-15, aşağıdaki commit'ler üzerinde.

| Kaynak | Commit | Lisans | İnsanın verdiği rol |
| --- | --- | --- | --- |
| [zazencodes-season-3 / software-factory-claude-code-v2](https://github.com/zazencodes/zazencodes-season-3/tree/main/src/software-factory-claude-code-v2) | `94f7ae7` | GPL-3.0 | Fabrikanın yapılandırması: istekten birleşmiş koda giden döngü |
| [mattpocock/skills](https://github.com/mattpocock/skills) | `5863806` | MIT | Skill paketi |
| [obra/superpowers](https://github.com/obra/superpowers) | `22f0b46` | MIT | Skill paketi |
| [addyosmani/agent-skills](https://github.com/addyosmani/agent-skills) | `39b723c` | MIT | Skill paketi |
| [cursor/plugins / pstack](https://github.com/cursor/plugins/tree/main/pstack) | `bf0c7cd` | MIT | **Yaklaşım örneği**: insanın aktardığına göre SpaceX AI'da kullanılan çalışma biçimi (pstack + TLA+ + Lean). Paketleme ya da Cursor eklentisi hedefi değildir. |

Durum sütunu: **var** (uygulandı), **kısmen**, **planlı** (yol haritasındaki kilometre taşı), **bırakıldı**.

## 1. zazencodes software factory v2

Ne: Bir Claude Code skill'i (orkestratör), sekiz ajan, üç script (`job`, `gate`, `route`) ve bir yapılandırma dosyası. GitHub issue kuyruğunu, her iş bir PR olacak şekilde birleşmiş koda çevirir. Hat: intake → route → worktree → spec-writer → builder → gate → paralel inceleyiciler → approver → `gh pr merge` ya da escalate.

| Fikir | softwary'deki yeri | Durum |
| --- | --- | --- |
| Orkestratör yalnızca koordine eder, kendisi dosya yazmaz | Döngü skill'i (design §6.4) | Var (V2: `run` skill'i yalnızca `run`, `job`, `status` çalıştırır) |
| İş durumunu tek bir script yazar, geçersiz geçişi reddeder (`TRANSITIONS` tablosu) | `job` scripti, `transitions.json` | Var (V2: tek yazar `sw_job_apply`, tablodan okunur) |
| Her ajan dosya okur, tek dosya yazar, tek satır yanıt verir; ayrıntı dosyadadır, orkestratörün bağlamı küçük kalır | Ajan sözleşmesi | Var (V2: tek satır yanıt, ayrıntı dosyada) |
| Kapı (`checks.sh`) incelemeden önce çalışır; kapıdan geçmeyen işi inceleyici görmez | `verify` | Var (V2: `job gate` PR'dan önce çalışır; kapıdan geçmeyen iş inceleyiciye gitmez) |
| Kapı ana daldaki denetim kopyasıyla çalışır; dal kendisini yargılayan denetimi değiştiremez | Birleştirme scripti (design §4) | Var (V3: korunan yol denetimi `verify`'dan önce gelir; kapı ve birleştirme entegrasyon dalındaki yapılandırma ve denetimlerle çalışır, D-89) |
| Korunan yollar (fabrikanın kendi denetimleri ve yapılandırması) | Korunan yollar (design §4) | Var (V3: `guard`, D-85) |
| Test korunmaz, ama zayıflatılmış ya da atlanmış test inceleyicide düşer | Test gevşetme denetimi | Var (V3: `guard` silinen test, kaybolan kriter kimliği ve `test-skip.conf` işaretleri, D-87) |
| Risk ve yüzey (UI, güvenlik) inceleyicileri ve modelleri seçer; seçim prompt'ta değil yapılandırmadadır | `risk`, `models.conf` | Kısmen: `risk` ve `models.conf` var (V2); yüzeye göre seçim sonra |
| Approver birleştirir ya da somut bir soruyla escalate eder; insan PR'ı birleştirerek onaylar | Approver ajanı | Var (V2: `decision.md`, `merge` ya da `job escalate`) |
| Birleştirmeden önce ana dalla eşitle ve kapıyı yeniden çalıştır | Birleştirme scripti | Var (V2: sıralı, `merge` eşitler ve her koşulu yeni SHA'da hesaplar); paralelde kuyruk V4 |
| Her iş bir PR'dır, `gh pr merge` ile birleşir; dal koruması ve zorunlu denetimler geçerlidir | Design §4 | Var (V2: `job pr`, `job ci`, `merge`; CI şablonu ve dal ayarları V1) |
| Durum dosyalardadır; oturum ölürse yeni çalıştırma her işi kaldığı yerden sürdürür | `.softwary/state/jobs/` | Var (V2: iş ve koşu dosyaları, `run next` yarım işi sürdürür) |
| İş başına tur sınırı (`max_rounds`), sonra insan | `loop.conf` | Var (V2: `max_rounds`, süre ve token sınırları) |
| İş başına maliyet ölçümü | Token bütçesi (D-50) | Var (V2: `job tokens`, `max_job_tokens`, `max_run_tokens`) |
| Kuyruk girdisi prompt'a değil, alıntılanmış veri olarak dosyaya girer | Güven ilkesi (design §7) | Kısmen: ajanlar girdiyi dosyadan okur; alıntılanmış veri biçimi sonra |

Alınmayan: kuyruk olarak GitHub issue'ları (softwary'nin kuyruğu plan dosyasıdır; issue tracker'a bağımlılık hedef dışıdır), HTML dashboard, kod ve prompt metinleri (GPL).

## 2. mattpocock/skills

Ne: Mühendislik ve yazı skill'leri. Bizi ilgilendirenler: `grill-me`/`grilling`/`grill-with-docs` (sorgulama), `domain-modeling` (sözlük ve ADR), `to-spec`, `to-tickets` (engelleme ilişkili "tracer bullet" iş blokları), `wayfinder` (tek oturuma sığmayan iş için karar haritası), `handoff`, `tdd`, `diagnosing-bugs`, `code-review` (standartlar ve spec ekseni), `software-factory` (fabrika tasarımı için ortak dil).

| Fikir | softwary'deki yeri | Durum |
| --- | --- | --- |
| Bütün dallar çözülene kadar, birer birer soru sorarak sorgulama | `define` | Var (V5: tek soru, önerili cevap, bütün dallar kapanana kadar; `discover` `define`'a katıldı, D-127) |
| Sözlük ve kararlar görüşme sürerken güncellenir | `CONTEXT.md`, ADR | Var (V5: `define` terimi `CONTEXT.md`'ye, zor geri alınır kararı önerilmiş ADR'ye görüşmede yazar) |
| Alan modelleme | Blueprint veri modeli | Var (V5: veri modeli, durum makineleri ve akışlar yapısal dosyalardır, `blueprint check` denetler, D-115, D-116) |
| Engelleme ilişkileri açık, uçtan uca ince iş blokları | Dilim `depends_on`, plan | Var (V2: `plan` skill'i, `NNN-S<n>` bağımlılıkları, `plan check`) |
| Oturum devri | `handoff` | Var (V5: `./softwary handoff` ve `handoff` skill'i, D-126) |
| İnceleme iki eksenli: kod standartları ve spec'e uyum | `reviewer` | Kısmen |
| Fabrika için "fren"ler: otomatik denetim, otomatik inceleme, insan incelemesi; tetikleyicileri yavaş açmak, her döngüyü birkaç denemede insana bağlamak | Kapılar, `reviewer`, tur sınırı | Var (V2: kapılar, tur sınırı, approver) |
| Bir çalıştırma insanı beklemez, biter; insanın sonraki değişikliği yeni çalıştırmayı başlatır | Escalate ve devam (design §6.4) | Var (V2: `job escalate`, `job resume`, `run next` `waiting:`) |

Alınmayan: issue tracker kurulumu ve triage etiketleri, TypeScript'e özgü skill'ler, uzak runner ve orkestratör altyapısı (softwary yerel çalışır, kendi sunucusu yoktur).

## 3. obra/superpowers

Ne: Süreç skill'leri: `brainstorming`, `writing-plans`, `executing-plans`, `subagent-driven-development`, `dispatching-parallel-agents`, `using-git-worktrees`, `test-driven-development`, `systematic-debugging`, `requesting-code-review`, `receiving-code-review`, `verification-before-completion`, `finishing-a-development-branch`.

| Fikir | softwary'deki yeri | Durum |
| --- | --- | --- |
| Önce test, kırmızıyı görmeden kod yok | `implement`, `implementer` | Var |
| Bitti demeden doğrulama çıktısı göster | Kural 2, `verify` | Var |
| Dosya yolları ve doğrulama adımları olan plan | `docs/plans/`, plan aşaması | Var (V2: ürün için `plan` skill'i; paketin kendi planları `docs/plans/`) |
| Görev başına taze subagent, ardından inceleme | `implementer`, `reviewer` | Var (V2: döngüde her iş temiz bağlamlı `implementer` ve `reviewer` çağrısıdır) |
| Temiz test tabanıyla izole worktree | Paralel yürütme | Planlı (V4) |
| Sistematik hata ayıklama (kök neden önce) | `diagnose` | Var (V7: önce hatayı yeniden üreten test, kök neden kanıtla, düzeltme `repro`'lu bir dilim olarak plana girer; kapı ve birleştirme testin tabanda düştüğünü, işte geçtiğini kendileri hesaplar, D-157) |
| İnceleme geri bildirimini körü körüne değil doğrulayarak almak | `implement` (değişiklik turu) | Kısmen: `changes` kararı yeni tur açar (`job review`); ayrı skill yok |

Alınmayan: "her yanıttan önce skill çağır" zorlaması (softwary aşamaları kapılarla bağlar, prompt baskısıyla değil); belge yolu `docs/superpowers/` (planlar `docs/plans/`'a taşındı).

## 4. addyosmani/agent-skills

Ne: Yaşam döngüsü skill'leri: fikir ve spec, planlama, artımlı uygulama, TDD, inceleme, güvenlik, belgeler ve ADR, CI/CD, gözlemlenebilirlik, teslim.

| Fikir | softwary'deki yeri | Durum |
| --- | --- | --- |
| Yaşam döngüsü evreleri ve evre başına kapı | Hat (design §6) | Var: tanım, blueprint, plan, döngü (V2) ve teslim (V7: `ship`) |
| Kalite çıtası yazılı bir sözleşmedir; ajan onu sessizce indiremez (`constraint-driven-development`) | `commands.conf`, muafiyetler | Var: kapılar ve süreli muafiyetler (V1) |
| Spec önce (`spec-driven-development`) | `specify`, `changes` kapısı | Var |
| ADR'ler ve belgenin koddan sapmasının yakalanması | `adr` kapısı, drift | Var: `adr` ve `drift` (V7: blueprint ile kod arasındaki sapma, kararlar `architecture/drift.md`'de, D-159) |
| Taze bağlamda karşıt görüşlü inceleme (`doubt-driven-development`) | `reviewer`, `spec-analyst` | Kısmen |
| İnce, doğrulanabilir artımlar (`incremental-implementation`) | Dilimler | Var |
| "Bahane tabloları" (ajanın kapıyı atlatmak için kullandığı gerekçeler ve karşılıkları) | Skill metinleri | Var (V3: `implement`, `implementer`, `run` ve `evaluate`'te `## Excuses`, D-95) |
| Teslimde gözlemlenebilirlik, kademeli yayın, geri alma planı | `ship` | Var (V7: sürüm notunun üç bölümü doldurulmadan PR açılmaz, D-155) |

Alınmayan: tarayıcı ve ön yüz skill'leri (stack'e özgü), performans optimizasyonu.

## 5. pstack — yaklaşım örneği

İnsanın notu: pstack, TLA+ ve Lean SpaceX AI'da birlikte kullanılan bir çalışma biçimi olarak verildi. Amaç pstack'i paketlemek ya da Cursor eklentisi yapmak değil, bu **yaklaşımı** softwary'nin ürettiği yazılıma uygulamaktır. (pstack'in kendi belgeleri SpaceX AI'dan ya da Lean'den adıyla söz etmez; bu bağlam insanın aktarımıdır.) Yol haritasındaki V9 "Cursor ve sürüm" ayrı bir karardır ("önce Claude Code, ardından Cursor") ve pstack'ten gelmez.

Ne: Cursor'da geliştirilen bir skill paketi. `poteto-mode` bir isteği oyun kitaplarından birine (özellik, hata, refactor, otonom çalışma, orkestrasyon, gönderim…) eşler; diğer skill'leri adımlar gerektirdikçe çağırır. Otuza yakın ilke skill'i küçük, birleştirilebilir dosyalardır. Çekirdek iddiası: "hızlı gitmek istiyorsan önce derine in"; tek ajana güvenebildiğin için paralelleşebilirsin.

| Fikir | softwary'deki yeri | Durum |
| --- | --- | --- |
| İlkeler küçük, ayrı, birleştirilebilir dosyalardır | `src/rules/` | Kısmen: tek dosya (`core.md`) |
| Tekrar eden bir düzeltmeyi metin olarak değil yapı olarak (lint, kontrol, script) kodlamak | İlke 1 (talimat değil kapı) | Var |
| Çalıştığını gerçek yapıt üzerinde kanıtla, vekile ya da öz bildirime güvenme | `verify`; kanıtın birleştirmede yeniden hesaplanması | Var (V3: `merge` `guard`, risk ve `verify`'ı birleştirilen SHA'da yeniden hesaplar) |
| Yalnızca bir çalıştırmayla kanıtlanan bulgular kalır (`interrogate`) | `reviewer` | Var (V3: kanıtsız bulgu yazılmaz, `evidence:` alanı, D-95) |
| Diff'in ötesindeki etki alanı ve güvenliğin tek bir olguyu çalıştırarak kanıtlanması (`blast-radius`) | `risk`, inceleme | Kısmen: `risk` var |
| Geri alınabilir işte insanı bekleme | İlke 10 | Var (V2: döngü insanı beklemez, somut bir soruyla escalate eder) |
| İşi her biri doğrulanabilir durumda biten küçük birimlere bölmek ve sırayı kendini kanıtlayacak şekilde dizmek | Dilimler, plan | Kısmen |
| Paylaşılan durumu seri hale getirmeden önce ayırmak; işlemleri idempotent yapmak | Paralel yürütme, kilitler, çöküşten devam | Planlı (V4) |
| Davranışı test et, gerçeklemeyi değil | `implement` | Planlı (skill metni) |
| Alanı modelle (durum taşıyan mantıkta) | Blueprint durum makineleri | Var (V5: `architecture/states/<varlık>.json`, durum diyagramı üretilir, D-116, D-124) |
| Bağlam penceresini koru: toplu çıktıyı subagent'a, ana iş parçacığına özet | Ajan sözleşmesi (tek satır yanıt, ayrıntı dosyada) | Var (V2) |
| **Biçimsel doğrulama** (aşağıda) | design §6.2, §7 | Var (V5: belirtim, değişmez cümleleri, varyant kanıtı, ihlal yolu, `model_check`; V8: kapsam ve eskime denetimi, `formal verified`, `formal trace`, `states tests`, `untested`/`unreplayed` drift öğeleri, isteğe bağlı `proof_check`, D-176..D-188; Lean'i proje kurar) |

### pstack'in biçimsel doğrulama yaklaşımı

`create-formal-verification-skill`, `maintain-formal-verification-skill` ve `statechart` skill'lerinden:

1. **Hedef koddan seçilir.** Bir hatanın en pahalıya patladığı ve testlerin en az ulaştığı söz: eşzamanlılık, yeniden denemeler, durum makineleri, ayrıştırıcılar, güvensiz kod. En kolay doğrulanacak yer değil, en güçlü hedef.
2. **Aracı soru seçer.** Olayların kötü bir sırada olup olamayacağı sorusunda küçük bir tasarım modeli üzerinde model denetleyici (varsayılan TLA+). Kodun her girdi için doğru davrandığı sorusunda kanıt asistanı (Lean gibi) ya da SMT tabanlı doğrulayıcı. En düşük maliyetle cevaplayan araç.
3. **Koda sadık.** Modelin her parçası okunabilir bir koda işaret eder; kodda bölünmez olan adım modelde de bölünmezdir; adlar repodan gelir.
4. **Başarısız olabilmeli.** Hiç başarısız olduğu görülmemiş bir denetim hiçbir şey kanıtlamaz: her özellik, kodun kasıtlı bozulmuş bir sürümünde başarısız gösterilir.
5. **Bulgu bulgudur.** Mevcut kod özelliği bozuyorsa karşı örnek kodun diliyle raporlanır; özellik ya da model geçsin diye zayıflatılmaz.
6. **Kapsam dürüsttür.** Neyin, hangi sınırlar ve varsayımlarla doğrulandığı ve neyin dışarıda kaldığı yazılır. Geçmek modeli ya da sınırı kapsar, bütün sistemi değil.
7. **Ucuz yeniden çalışır.** Tek komut, sabit araç sürümü, her ilgili değişiklikte çalıştırılacak kadar kısa.
8. **Kodla birlikte yürür.** Her denetimin kapsadığı dosya ve fonksiyonlar ile en son doğrulandığı commit kaydedilir. Kapsanan kod değişince bakım döngüsü her sonucu ayırır: uyumlu, güncellendi, **hata** (model kodu doğru anlatıyor, kod özelliği bozuyor), engelli. Eskimiş bir modelin geçmesi en tehlikeli durumdur, çünkü kanıt gibi görünür.
9. **Okunabilir sonuç.** Özellik ve zarar birer düz cümledir. `statechart` TLA+ modelini model denetleyiciden geçirir, her ihlal için en kısa yolu okurun dilinde verir ve sistemi bir Mermaid durum diyagramı olarak çizer. Bulunan her yol gerçek koda karşı adım adım yeniden oynatılır; oynamazsa önce modelin yanlış olduğu varsayılır.

### softwary'deki durum

İnsan kararıyla (D-63, 2026-11-15) yaklaşım ürüne uygulanır; ayrıntı design §6.2 ve §7'de:

- Blueprint'teki her durum makinesi ve eşzamanlılık, yeniden deneme ya da çöküş içeren her akış için TLA+ belirtimi. Değişmezler insanın onayladığı cümlelerdir; belirtim blueprint onayından önce model denetleyiciden geçer, sonra `model_check` olarak her `verify`'da çalışır (V5'te var: `formal check`, `formal install`, `model_check`, D-117..D-123).
- Yukarıdaki 4, 5 ve 8. maddeler kapıdır: bozulmuş varyantta başarısızlık kanıtı, bulguyu zayıflatma yasağı, kapsam kaydı ve sapma denetimi (V5'te kayıt, V8'de gerçek dosya ve fonksiyon denetimi, eskime ve `formal verified`).
- Kanıt asistanı (Lean) yalnızca R3 riskli, saf algoritmik çekirdekler için isteğe bağlıdır (V8: kanıt `architecture/proofs/`'ta, komutu projenin `proof_check`'i; paket Lean kurmaz).
- Değişmeyen sınır: belirtimin doğruluğu kanıtlanır, kodun belirtime uyduğu kanıtlanmaz; bu boşluk karşı örneklerin koda karşı yeniden oynatılması (`formal trace`, `CE-` kimliği) ve belirtimden türetilen testlerle (`states tests`, `ST-` kimliği) daraltılır (V8).
- softwary'nin kendi paralel birleştirme protokolü de TLA+ ile belirtilir (V4).

Alınmayan: `poteto-mode`'un çok modelli panel düzeni (softwary `models.conf` ile Opus ve Sonnet'e iki rol verir), arena ve sürü gibi paralel aday üretimi, Cursor'a özgü özellikler (bugbot, otomasyonlar), TypeScript'e özgü skill'ler.

## Karşılıklı eşleme

Kaynaklar aynı fikri farklı adlarla taşır. softwary'deki karşılıkları:

| softwary | zazencodes | mattpocock | superpowers | addyosmani | pstack |
| --- | --- | --- | --- | --- | --- |
| Kapı (`verify`) | `gate` + `checks.sh` | otomatik denetim (fren) | verification-before-completion | constraint-driven-development | prove-it-works |
| Tanım ve sorgulama | intake | grill-me, grilling | brainstorming | interview-me, idea-refine | interrogate, sharpen |
| Plan ve dilimler | spec-writer | to-spec, to-tickets, wayfinder | writing-plans | planning-and-task-breakdown | sequence-verifiable-units |
| Uygulama | builder | implement, tdd | subagent-driven-development, TDD | incremental-implementation | poteto-mode (feature) |
| İnceleme | reviewer-* | code-review | requesting-code-review | code-review-and-quality, doubt-driven | interrogate, blast-radius |
| Birleştirme | approver + `gh pr merge` | — | finishing-a-development-branch | git-workflow-and-versioning | shipping |
| Paralel | concurrency | chief-of-staff | worktrees, dispatching-parallel-agents | — | swarm, autopilot |
| Hata ayıklama | — | diagnosing-bugs | systematic-debugging | debugging-and-error-recovery | bug-fix, forensics |
| Biçimsel doğrulama | — | — | — | — | create/maintain-formal-verification, statechart |
