# Yol haritası

Paket M0'dan sonra on bir kilometre taşıyla tamamlanır ve M4'ün sonunda gerçek bir projede kullanılabilir hale gelir. Buradaki her satır bir niyet ve verilmiş kararlardır; ayrıntılı spec, sırası geldiğinde ve önceki kilometre taşlarından öğrenilenlerle yazılır. Arşiv sekmesindeki notlar o spec'lerin girdisidir.

| No | Kilometre taşı | Ne teslim eder | Verilmiş kararlar |
| --- | --- | --- | --- |
| M1 | Dağıtım | `core.md`, `AGENTS.md` bloğu, `sync` ve Claude Code, Cursor, Codex hedef scriptleri | Tek kaynak, üretilen dosyalar commit'lenir, mevcut `AGENTS.md` korunur |
| M2 | Yapıtlar | Şablonlar, `model validate`, `views`, `trace`, `risk`, `status` | CALM kaynak, Mermaid `jq` ile üretilir, kabul kriteri kimliği düz metin aramasıyla izlenir |
| M3 | Kurulum ve kapılar | `setup` skill'i, git hook'ları, CI şablonu, ADR denetimi, `upgrade` | CI GitHub Actions, mevcut repolarda taslak model ve taban çizgisi |
| M4 | Hat | Keşiften incelemeye kadar skill'ler, üç subagent, kalan kurallar | Yazan incelemez, her değişikliğin bir spec'i var |
| M4a | Sıralı döngü | `./softwary next`, `next` ve `handoff` skill'leri, `softwary-loop`, durma koşulları | Döngü onay vermez ve birleştirme yapmaz |
| M4b | Paralel dilimler | `touches`, `scope`, sahiplenme kilidi, `next --parallel`, `bootstrap` | Worktree'leri kullanıcı açar, ortak dosyalar dilim dallarında değişmez |
| M4c | Arka plan alt oturumları | Çalıştırıcı sözleşmesi, herdr eşlemesi, `softwary-dispatch`, `./softwary queue` | ADR ve spec ana oturumda, herdr isteğe bağlı, durumun kaynağı repo |
| M5 | Drift | Yapı denetimi, `drift-auditor`, `maintain` | Üç katman: sözleşme, yapı, anlam; kararı insan verir |
| M6 | Teslim ve işletim | `ship`, `diagnose` | Üretime dağıtım insan onayıyla |
| M7 | Bağımsızlık kanıtı | İkinci bir stack'te gerçek kullanım | Paket reposunda belge dışında değişiklik gerekmemeli |
| M8 | İlk açık sürüm | Kurulum kanalları, `uninstall`, İngilizce belgeler, skill değerlendirmeleri, `v0.1.0` | MIT, kademeli benimseme (`gates`, `specs`, `full`), telemetri yok, anlamsal sürümleme |

## Sıra kuralları

- **Bir seferde bir kilometre taşı.** Bir sonrakinin spec'i, önceki bitmeden yazılmaz.
- **M4'ten sonra gerçek kullanım.** Döngü, paralel dilimler ve alt oturumlar, hat gerçek bir projede kullanıldıktan sonra tasarlanır. Bu üçünün arşivdeki ayrıntıları o deneyime göre değişebilir.
- **Paket kendi üzerinde.** M4'ten itibaren paketteki her değişiklik paketin kendi hattından geçer.
- **Sıra değişebilir.** M5, M6 ve M4a ile M4c arasındaki sıra, kullanımda en çok eksikliği hissedilene göre yeniden belirlenir.

## Sonraki fikirler

Karar verilmedi, yalnızca not:

- CI'da başsız ajanla anlamsal drift denetimi.
- herdr dışındaki çalıştırıcılar için eşlemeler.
- Issue tracker ile iki yönlü eşitleme.
