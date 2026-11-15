# softwary — Çekirdek tasarım (v2)

Nov 15, 2026 · @Ufuk Cem Delice

softwary, mühendisin anlattığı bir ürünü onunla birlikte tanımlayan, tasarlayan, bağımsız bloklara bölüp test önce yürüten, kapılardan ve bağımsız incelemeden geçirip birleştiren ve bunu bütün SDLC boyunca sürdüren, araçtan ve stack'ten bağımsız, MIT lisanslı açık kaynak bir pakettir. Bu belge her oturumda okunan tek kalıcı tasarımdır; v1 tasarımının yerini alır (v1, git geçmişinde `eb2f8bf`'tedir). Kilometre taşlarının ayrıntısı kendi spec'lerinde, sırası `docs/roadmap.md`'dedir. Çelişki olursa bu belge geçerlidir.

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

Her kaynağın rolü, alınan ve alınmayan fikirler, durumları ve pstack'in biçimsel doğrulama yaklaşımının ayrıntısı `docs/sources.md`'dedir. Aşağıdaki tablo özettir.

| Kaynak | Alınan fikir | v2'deki yeri |
| --- | --- | --- |
| softwary v1 | Script kapıları (`verify`, `trace`, `adr`, `changes`), CALM modeli kaynak, `sync` ile araç dağıtımı, `commands.conf` sözleşmesi, kriterden teste izlenebilirlik | Çekirdek |
| zazencodes factory v2 | Orkestratör yalnızca koordine eder; durumu yalnızca bir script yazar ve geçersiz geçişi reddeder; her ajan tek dosya yazar, tek satır yanıt verir; inceleyiciler kapıdan geçmemiş işi görmez; kapı ana daldaki denetimlerle çalışır; korunan yollar; riske göre inceleyici seçimi; approver birleştirir ya da somut bir soruyla escalate eder; birleştirmeden önce eşitleme ve yeniden kapı; durum dosyalarda, oturum ölürse devam | Döngü (§6.4) |
| mattpocock/skills | Bütün dallar çözülene kadar sorgulama; sözlük ve kararların görüşmede güncellenmesi; alan modelleme; engelleme ilişkili "tracer bullet" iş blokları; oturum devri | Tanım, blueprint, planlama |
| obra/superpowers | Temiz test tabanıyla worktree; dosya yolları ve doğrulama adımları olan plan; görev başına taze subagent; bitirmeden önce doğrulama; sistematik hata ayıklama | Planlama, uygulama, işletim |
| addyosmani/agent-skills | Yaşam döngüsü evreleri; kalite çıtası ve kapıyı oyunlamaya karşı önlem; taze bağlamda karşıt görüşlü inceleme; "bahane tabloları"; teslimde gözlemlenebilirlik, kademeli yayın, geri alma planı | İlkeler, inceleme, teslim |
| cursor/plugins pstack (yaklaşım örneği; paketleme hedefi değil) | İlkeleri küçük, birleştirilebilir dosyalar olarak tutmak; yalnızca kanıtlanan bulguların kaldığı inceleme; etki alanı analizi; durum makineleri ve biçimsel doğrulama; "çalıştığını kanıtla"; geri alınabilir işte insanı bekleme | İnceleme, blueprint, biçimsel doğrulama |

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
10. **Geri alınabilir işte bekleme, geri alınamazda dur.** Döngü insanı yalnızca onay noktalarında, escalate'te ve geri alınamaz eylemlerde bekler. Üretim dalına alma ve dağıtım geri alınamaz sayılır: döngü yalnızca entegrasyon dalına birleştirir. *(yeni)*

## 4. İnsan denetimi ve güven sınırı

İnsanın devredilemez kararları: **ürün tanımı onayı, blueprint onayı, escalate edilen işler, entegrasyon dalının üretim dalına alınması, drift kararı, üretime dağıtım.**

**Dallar.** İki dal vardır; adları `commands.conf`'ta `integration_branch` ve `production_branch` ile ayarlanır (örneğin `main` ve `master`). Varsayılan ad yoktur: şablon ikisini `UNSET` taşır ve `setup` sorar (D-52). `verify`, `adr`, `changes` ve `risk` `--base` verilmezse entegrasyon dalına karşı çalışır. Döngü her işi kendi worktree'sinde ve dalında yürütür, entegrasyon dalına bir PR açar ve birleştirir. Üretim dalına alma `ship` adımıdır ve insan onayıyla yapılır.

**GitHub PR ve CI zorunludur.** Her iş bir PR'dır; entegrasyon dalının koruması CI'ın yeşil olmasını şart koşar ve birleştirme `gh pr merge` ile yapılır. Ajanlar insanın git ve GitHub kimliğiyle çalıştığı için dal koruması insan incelemesi şart koşamaz (kişi kendi PR'ını onaylayamaz); zorunlu koşul CI'dır.

**Onaylar metin alanı değildir.** `./softwary approve product|blueprint`, onaylanan dosyaların içerik özetlerini kaydeder. Planlama ve birleştirme scriptleri özet uyuşmazsa reddeder. Bu koruma, onaydan sonra yapılan değişikliği yakalar (tamper-evident); ajanın `approve`'u kendisinin çalıştırmasını engellemez, onu yasaklayan bir kuraldır ve olay günlüğünde görünür. İnsan bu düzeyi yeterli buldu (2026-11-15); daha güçlü sınır (imzalı onay ya da ajanlar için ayrı GitHub kimliği) sonraya bırakıldı.

**Birleştirme kararı approver ajanınındır**, ama approver yalnızca birleştirme scriptini çağırabilir. Script şunları kendisi hesaplar ve biri tutmazsa reddedip işi insana gönderir:

- iş, entegrasyon dalıyla eşitlendikten sonra o SHA üzerinde yerel kapı ve PR'ın CI'ı yeşil,
- diff, dilimin `touches` alanıyla bildirdiği yolların içinde,
- test silinmemiş, atlanmamış (`skip`, `only`), kriter kimliği kaldırılmamış,
- korunan yollara dokunulmamış: `.softwary/`, CI, `CODEOWNERS`, `PRODUCT.md`, blueprint'in bağlayıcı kısımları,
- risk kademesi R3 değil: R3 her zaman insana gelir,
- korunan yol değişikliği yok: her zaman insana gelir,
- tur ve bütçe sınırı aşılmamış.

Her birleştirme gerekçesiyle `decision.md`'ye ve olay günlüğüne yazılır.

## 5. Yapıtlar

| Yapıt | Yol | Onay |
| --- | --- | --- |
| Ürün tanımı | `product/PRODUCT.md`: problem, kullanıcılar, kapsam ve dışı, özellikler, her özellik için kimlikli kabul örnekleri (`EX-<özellik>-NN`), işlevsel olmayan gereksinimler, kısıtlar, başarı ölçütleri | İnsan (`approve product`) |
| Sözlük | `CONTEXT.md` | Görüşmede güncellenir |
| Blueprint, bağlayıcı | `architecture/model/system.calm.json` (bileşenler, ilişkiler), `architecture/data/model.json` (varlıklar, alanlar, ilişkiler), `architecture/contracts/` (OpenAPI) | İnsan (`approve blueprint`) |
| Blueprint, bilgilendirici | `architecture/flows/*.json` (çok bileşenli akışlar), `architecture/states/*.json` (durumlu varlıklar); Mermaid görünümleri `views` ile üretilir | Yok; döngü güncelleyebilir |
| Biçimsel belirtim | `architecture/formal/<ad>.tla` ve `.cfg` (TLA+ modeli), `architecture/formal/<ad>.md` (her değişmezin düz cümlesi ve zararı, kapsadığı dosya ve fonksiyonlar, sınırlar ve varsayımlar, son doğrulandığı commit, bozulmuş varyant kaydı); R3 saf algoritmalar için isteğe bağlı kanıt (Lean) | Değişmez cümleleri bağlayıcıdır: insan (`approve blueprint`); model ve kapsam kaydı döngüde güncellenebilir |
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

Onaylı üründen bileşen modeli, veri modeli, sözleşmeler; yalnızca birden çok bileşene dokunan akışlar için akış tanımı; durumlu varlıklar için durum makinesi; ADR'ler. Her durum makinesi ve eşzamanlılık, yeniden deneme ya da çöküş içeren her akış için bir TLA+ belirtimi yazılır (§7): kurallar insanın okuyacağı cümlelerle değişmez olarak konur, model denetleyiciden geçer ve sonuç okurun dilinde bir durum diyagramı ile her ihlalin en kısa yolu olarak gösterilir. Taze bağlamlı bir eleştirmen blueprint'i kırmaya çalışır. Kapı: `./softwary blueprint check` (her özelliğin bir bileşene ve gerekiyorsa bir akışa bağlanması, akışların var olan bileşen ve varlıklara başvurması, modellerin geçerliliği, belirtim gereken her durum makinesi ve akışın bir belirtimi olması, `model_check`'in geçmesi ve her değişmezin bozulmuş bir varyantta başarısız gösterilmiş olması) ve `approve blueprint` (değişmez cümleleri dahil).

### 6.3 Planlama (`plan`)

Blueprint özellik başına spec'e, spec dilimlere bölünür. Her spec kriteri `PRODUCT.md`'deki bir kabul örneğine bağlanır. Taze bağlamlı `spec-analyst` her spec'i denetler. `trace` ve analist PASS ise planlama scripti spec'i `approved` yapar; ürün ya da bağlayıcı blueprint değişikliği gerektiren spec escalate edilir. Kapı: `trace`, bağımlılık grafiği döngüsüz.

### 6.4 Döngü (`run`)

Tek bir orkestratör oturumu (Claude Code'da bir skill) kuyruğu boşaltır. Bir dilim, `depends_on`'u birleşmiş ve `touches`'ı çalışan işlerle ve ortak dosyalarla (kilit dosyaları, migration'lar, `CONTEXT.md`, üretilen dosyalar) kesişmiyorsa başlar; en fazla `concurrency` iş aynı anda.

Her iş: kendi worktree'si, dalı ve bağımlılık hazırlığı (`bootstrap`) → `implementer` (test önce, `verify --fast`) → kapı (entegrasyon dalındaki denetimlerle tam `verify`) → entegrasyon dalına PR ve CI → inceleyici (kanıtlı bulgular) → `approver` → birleştirme kuyruğu. Birleştirmeler tek tek yapılır: eşitle, o SHA üzerinde kapı ve CI, `gh pr merge`. Entegrasyon dalı kırmızıya dönerse hat durur ve son birleştirme geri alınır.

Sınırlar ve gözlem (`.softwary/config/loop.conf`, varsayılanlar insan onaylı):
- iş başına en fazla 3 tur, sonra insan,
- iş başına 45 dakika, koşu başına 4 saat,
- aynı anda 1 iş; paralel kilometre taşından sonra 3,
- token üst sınırı (iş ve koşu başına; abonelikte maliyet dolar değil token ile sınırlanır),
- kararsız testler için kural: bir kez yeniden çalıştır; yine kararsızsa işi durdur ve insana bildir, testi asla gevşetme,
- `./softwary status`: işler, aşamalar, süreler ve escalate kutusu; bir iş insanı beklerken diğerleri sürer.

İş durum makinesi küçük olduğu için TLA+ ile değil, `transitions.json` üzerinden her durum × olay çiftini deneyen kapsamlı testlerle doğrulanır. Paralel birleştirme protokolü (çöküşler dahil) TLA+ ile belirtilir.

### 6.5 Teslim ve işletim

`ship`: entegrasyon dalını üretim dalına alma önerisi, sürüm notu, gözlemlenebilirlik, kademeli yayın ve geri alma planı; dağıtım insan onayıyla. `diagnose`: önce hatayı yeniden üreten test. `maintain`: drift denetimi.

## 7. Güven, değerlendirme ve biçimsel doğrulama

- **Değerlendirme (eval).** Approver'a güvenmek kanıt ister. Bilinçli olarak bozuk diff'ler içeren bir örnek repo ile yakalama oranı ölçülür; döngü varsayılan olarak ancak bu ölçüm belirlenen eşiği geçtiyse kendi kendine birleştirir.
- **Ajan izinleri.** Arka plan ajanlarının ağ, `gh` ve gizli bilgi erişimi kısıtlanır; yalnızca kendi dalına push eder.
- **Biçimsel doğrulama (ürün).** Yaklaşım pstack'ten (`docs/sources.md` §5, insan kararı D-63): biçimsel doğrulama, hatanın en pahalı ve testlerin en zayıf olduğu yere uygulanır ve araç soruya göre seçilir.
  - *Ne zaman:* blueprint'teki her durum makinesi ve eşzamanlılık, yeniden deneme ya da çöküş içeren her akış. Olayların kötü bir sırada olup olamayacağı sorusu TLA+ modeli ve model denetleyici (TLC) ile cevaplanır. R3 riskli, saf algoritmik bir çekirdeğin (para hesabı, yetki kuralı, ayrıştırıcı) her girdi için doğruluğu gerekiyorsa kanıt asistanı (Lean) isteğe bağlıdır; zorunlu değildir, çünkü maliyeti her projeye uymaz.
  - *Kurallar (kapı):* her değişmezin düz bir cümlesi ve zararı vardır ve insan bunları blueprint onayında onaylar. Model koda sadıktır: her parçası bir dosyaya ve fonksiyona işaret eder, koddaki bölünmez adım modelde de bölünmezdir. Her değişmez bozulmuş bir varyantta başarısız gösterilir; hiç başarısız olmamış denetim kanıt sayılmaz. Mevcut kod bir değişmezi bozuyorsa bu bir bulgudur; değişmez ya da model geçsin diye zayıflatılmaz (korunan yol, §4). Kapsam dürüsttür: sınırlar, varsayımlar ve dışarıda kalanlar yazılır.
  - *Sürekli:* `model_check` belirtim olan projede zorunludur ve her `verify`'da çalışır; kısa ve tek komuttur. Kapsam kaydındaki dosyalar son doğrulanan commit'ten beri değiştiyse `model_check` bunu bildirir ve sapma denetimi her belirtimi şu sonuçlardan birine bağlar: uyumlu, güncellendi, hata (model kodu doğru anlatıyor, kod kuralı bozuyor), engelli. Eskimiş bir modelin geçmesi en tehlikeli durumdur, çünkü kanıt gibi görünür.
  - *Sınır:* belirtimin doğruluğu kanıtlanır, kodun belirtime uyduğu kanıtlanmaz. Bu boşluk iki yolla daraltılır: model denetleyicinin bulduğu her karşı örnek gerçek koda karşı adım adım test olarak yeniden oynatılır (oynamazsa önce model yanlış sayılır), ve kabul testleri belirtimin durum ve geçişlerinden türetilir.
  - *Araç:* TLC Java gerektirir; belirtimi olan projede `bootstrap` ve CI'ın kurulum adımı onu kurar. Alloy veri modeli kısıtları için isteğe bağlıdır.
- **Biçimsel doğrulama (paket).** softwary'nin kendi paralel birleştirme protokolü TLA+ ile belirtilir (değişmezler: kapısı yeşil olmayan SHA entegrasyona girmez; `touches`'ı kesişen iki iş aynı anda çalışmaz; iki adım arasındaki çöküş kurtarılabilir; her iş bir son duruma ya da insana ulaşır). Burada TLC yalnızca paketin geliştirme bağımlılığıdır.

## 8. Araçlar, modeller ve uygulama dili

Önce Claude Code, sonra Cursor.

Rol başına model (`.softwary/config/models.conf`, insan kararı 2026-11-15):

| Rol | Model |
| --- | --- |
| Kritik planlama: `define`, `blueprint`, blueprint eleştirmeni, `plan`, `spec-analyst` | Opus |
| Uygulama: `implementer` | Sonnet |
| Uygulayıcının danışmanı: takıldığında ya da bir tasarım belirsizliğinde Sonnet'in çağırdığı, yalnızca okuyan ve öneri veren ajan | Opus |
| İnceleme ve birleştirme kararı: `reviewer`, `approver` | Opus (yazandan farklı model) |

Danışman kod yazmaz ve durum değiştirmez; önerisi uygulayıcının notlarına kaydedilir.

Kapılar ve `job`, `queue`, `merge` scriptleri POSIX `sh` ve `jq` ile, dosyalar üzerinde saf fonksiyonlar olarak kalır; kilitler `mkdir` ile (Git Bash'te `flock` yok). Durum kodu gerçek eşzamanlılık ilkelleri gerektirir ya da yaklaşık 500 satırı geçerse dil yeniden düşünülür.

## 9. v1'den değişenler

- Spec onayı insandan alınıp `PRODUCT.md` örneklerine bağlı otomatik onaya geçti.
- Birleştirme approver'a geçti, ama hedef entegrasyon dalıdır; üretim dalına alma ve dağıtım insanda.
- GitHub PR ve CI döngünün zorunlu parçası oldu; dal koruması insan incelemesi yerine CI'ı şart koşar.
- Taban çizgisi, süreli muafiyet anlamına geldi.
- Yol haritasındaki M4a ("döngü onay vermez ve birleştirme yapmaz"), M4b ("worktree'leri kullanıcı açar") ve D-44 v2 ile geçersiz olur.

## 10. Paket mimarisi

Kurulum dosya kopyalamaktır. Scriptler POSIX `sh` ile yazılır; ek bağımlılıklar `git` ve `jq`. Paket içeriği İngilizce, paketin kendi belgeleri Türkçedir.

```
<repo>/
  softwary              sarmalayıcı, .softwary/bin/softwary'yi çağırır
  AGENTS.md  CLAUDE.md  üretilir (yönetilen blok)
  CONTEXT.md            alan sözlüğü
  .softwary/
    bin/ lib/ rules/ skills/ agents/ templates/ targets/ hooks/   yönetilen
    config/             commands.conf, risk.conf, tools.conf, waivers.conf, loop.conf, models.conf
    local/              projeye özel ekler
    state/              kayıtlar, iş durumu, olay günlüğü; git'e eklenmez
  product/              PRODUCT.md
  architecture/         model/ data/ flows/ states/ contracts/ formal/ views/ decisions/
  specs/<no>-<ad>/      spec.md, slices/, reviews/
  .claude/ .cursor/ .agents/ .codex/    üretilir
```

- **Yönetilen** dosyalar güncellemede üzerine yazılır. **Projeye ait** dosyalara (`config/`, `local/`, `product/`, `architecture/`, `specs/`, `CONTEXT.md`) paket dokunmaz. **Üretilen** dosyalar commit'lenir ve güncellikleri CI'da denetlenir.
- Mevcut `AGENTS.md` korunur; paket yalnızca kendi işaretçileri arasını yazar.
- Aynı adlı `local/` dosyası yönetileni ezer.

## 11. Komut sözleşmesi

Skill'ler, hook'lar ve CI yalnızca sözleşme isimlerini kullanır. Gerçek komutlar `.softwary/config/commands.conf` dosyasında `anahtar = değer` biçiminde durur.

| Anahtar | Garanti | Durum |
| --- | --- | --- |
| `format_check`, `lint`, `typecheck` | Biçim, statik analiz ve tip denetimi temiz | Zorunlu |
| `test`, `build` | Testler geçiyor, çıktı üretiliyor | Zorunlu |
| `security` | Bağımlılık açığı ve gizli bilgi taraması temiz | Zorunlu |
| `contract_check` | Uygulama sözleşme dosyalarıyla uyumlu | Sözleşme varsa zorunlu |
| `arch_check` | Modeldeki bağımlılık kurallarına uyuluyor | Birden fazla bileşen varsa zorunlu |
| `run`, `deploy`, `bootstrap` | Yerelde başlatma, dağıtım, yeni kopyayı (ve worktree'yi) hazırlama | İsteğe bağlı; döngüde `bootstrap` zorunlu |
| `model_check` | `architecture/formal/` belirtimleri model denetleyiciden geçiyor ve kapsam kayıtları güncel | Belirtim varsa zorunlu (§7) |

Bir değer üç biçimden biridir: bir komut (çıkış kodu 0 ise geçer), `UNSET` (zorunlu anahtarda hata) ya da `NONE: <gerekçe>` (atlanır, gerekçe raporda görünür). `test_paths` ve `src_paths` komut değil ayardır.

Paketin kendi komutları: `verify` (`--fast`, `--base`), `trace`, `adr`, `changes`, `model validate`, `views`, `risk`, `status`, `sync`, `doctor`, `upgrade`; v2 ile `approve`, `product check`, `blueprint check`, `job`, `run`, `drift`. Her biri ilgili kilometre taşında eklenir.

`verify` ucuzdan pahalıya çalışır ve ilk hatada durmaz: paketin kendi denetimleri (`sync`, `model`, `views`, `trace`, sonra entegrasyon dalına ya da `--base`'e karşı `adr` ve `changes`; henüz commit yoksa bu ikisi `SKIP (no commits yet)`), biçim ve statik denetimler, test ve derleme, sözleşme ve mimari ve güvenlik. `--fast` yalnızca biçim, lint ve tip denetimlerini çalıştırır. Çıktı ajanın okuması içindir:

- Kontrol başına tek satır: `PASS`, `FAIL` ya da `SKIP (gerekçe)`.
- Hatada çıktının yalnızca son satırları basılır, tam kayıt `.softwary/state/logs/` altına yazılır.
- Çıkış kodları: `0` geçti, `1` başarısız, `2` yapılandırma eksik.
- Süresi dolmamış bir muafiyeti olan başarısız kontrol `WAIVED (<gerekçe>, until <tarih>)` satırıyla görünür ve sonucu kırmızı yapmaz (§3 ilke 4). Süresi dolmuş muafiyet `FAIL`'i değiştirmez, satıra `waiver expired <tarih>` ekler; geçen bir kontrolün muafiyeti `PASS (waiver no longer needed)` gösterir. Muafiyet yalnızca proje denetimlerine verilir, paket denetimlerine verilemez.
- `doctor` proje komutlarını çalıştırmaz: yapılandırılmış anahtar `PASS (configured, not run)` yazar.

## 12. Araç dağıtımı

Kaynak bir kez yazılır, `sync` her araç için bir hedef scriptiyle çevirir. Öncelik Claude Code, sonra Cursor'dur (§8). Yeni araç eklemek tek bir hedef scripti eklemektir.

| Kaynak | Claude Code | Cursor | Codex |
| --- | --- | --- | --- |
| Kuralların girişi | `CLAUDE.md` | `AGENTS.md` | `AGENTS.md` |
| Skill'ler | `.claude/skills/` | `.cursor/skills/` | `.agents/skills/` |
| Subagent'lar | `.claude/agents/*.md` | `.cursor/agents/*.md` | `.codex/agents/*.toml` |

Skill üst bilgisi yalnızca `name` ve `description` taşır. Subagent'ı desteklemeyen araçta rol skill olarak üretilir ve temiz bir oturumda çalıştırılır.

## 13. Verilmiş kararlar

- Paket adı `softwary`, repo herkese açık, lisans MIT. POSIX `sh`, `git`, `jq`; düz `anahtar = değer` yapılandırma. Üretilen dosyalar commit'lenir.
- Kaynaklardan yalnızca fikir alınır, metin ya da kod alınmaz (zazencodes GPL-3.0).
- Döngü worktree'den entegrasyon dalına (`main`) PR ile birleştirir; üretim dalı (`master`) ayrıdır ve ona alma insan onayıyla yapılır.
- Onay güven sınırı içerik özetleridir (tamper-evident); daha güçlü sınır sonraya bırakıldı.
- İlk hedef boş repodur; mevcut repo proje tamamlanınca eklenir.
- GitHub PR ve CI döngünün zorunlu parçasıdır; CI şablonu GitHub Actions içindir.
- R3 ve korunan yol değişiklikleri her zaman insana gelir. Bütçe varsayılanları §6.4'tedir; kullanıcı abonelikle çalıştığı için maliyet token ile sınırlanır.
- Opus kritik planlamayı ve incelemeyi, Sonnet uygulamayı yapar; Sonnet gerektiğinde Opus'u danışman olarak kullanır.
- Biçimsel doğrulama ürüne uygulanır: blueprint'teki durum makineleri ve kritik akışlar için TLA+ ve `model_check` kapısı (V5); Lean yalnızca R3 saf algoritmalar için isteğe bağlı (D-63).
- v2 tasarımı bağımsız bir danışman incelemesinden (Fable, 2026-11-15) geçti; bulguları ve v1'den geçersiz kalanlar `docs/decisions.md`'dedir.

## 14. Yapım biçimi

- Her kilometre taşı kendi spec'iyle yapılır. Spec, sırası geldiğinde ve önceki kilometre taşı birleştikten sonra yazılır. Gerçek kullanım denemesi bütün proje bitince yapılır (D-64).
- Yapıcı önce plan sunar, onaydan sonra testi önce yazarak uygular ve kabul kriterlerini çıktıyla gösterir.
- Belgede olmayan kararlar ilkelere göre verilir ve `docs/decisions.md` dosyasına yazılır.
- Bir karar değişirse önce bu belge değişir, sonra kod.
- Paket, hattı kurulduğu andan itibaren kendi üzerinde kullanılır.
