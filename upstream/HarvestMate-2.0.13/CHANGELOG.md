# HarvestMate changelog

## 2.0.13

- Gamepad interface turned on but no gamepad connected: the game then ignores the "gamepad only" soft target setting, and the gather key and highlighting did nothing. The addon now checks for a connected gamepad and switches soft target to work with the mouse too.
- `/hm near` also shows the number of connected gamepads.

- Интерфейс геймпада включён, а геймпад не подключён: игра тогда не применяет мягкую цель «только для геймпада», и клавиша сбора с подсветкой не работали. Теперь аддон проверяет, подключён ли геймпад, и включает мягкую цель и для мыши.
- `/hm near` показывает ещё и число подключённых геймпадов.

## 2.0.12

- Soft target interact is a game setting kept on each computer separately. If you turned it on once and it's off on another PC (or after a game settings reset, or it was set for gamepad only), the addon now turns it back on at login and tells you in chat. The gather key and node highlighting work right away. `/hm soft off` still turns it off for good.

- Мягкая цель взаимодействия — настройка игры, которая хранится на каждом компьютере отдельно. Если вы её уже включали, а на другом ПК она выключена (или настройки игры сбросились, или она включена только для геймпада), аддон при входе включает её снова и пишет об этом в чат. Клавиша сбора и подсветка сразу работают. `/hm soft off` по-прежнему выключает её насовсем.

## 2.0.11

- Minimap: since the game update of 12 November 2026 (build 70938), addons can't read minimap tooltips. The addon no longer watches the tooltip window for them, and `/hm tip` says so plainly. If Blizzard opens minimap tooltips again, the skill there will come back on its own.

- Миникарта: с обновления игры 12 ноября 2026 года (билд 70938) аддоны не могут читать подсказки миникарты. Аддон больше не следит за окном подсказки ради них, а `/hm tip` прямо об этом сообщает. Если Blizzard снова откроет подсказки миникарты, навык там вернётся сам.

## 2.0.10

- Minimap: the addon now also recognises the minimap tooltip by the cursor being over the minimap, whoever owns the tooltip and however the game fills it in.
- `/hm tip` tells you if the game shows the minimap tooltip but hides its text from addons, and how many minimap tooltips reached the addon and by which route.

- Миникарта: аддон узнаёт подсказку миникарты и по тому, что курсор над миникартой, кому бы ни принадлежала подсказка и как бы игра её ни заполняла.
- `/hm tip` сообщает, если игра показывает подсказку миникарты, но скрывает её текст от аддонов, и сколько подсказок миникарты дошло до аддона и каким путём.

## 2.0.9

- Minimap: skill on herbs and veins is back. On this game client the minimap writes its text straight into the tooltip, without the tooltip data the addon was waiting for; the addon now catches such tooltips itself.
- `/hm tip` now also shows the last other tooltip and its owner if no node tooltip was seen.

- Миникарта: навык на траве и жилах снова показывается. В этом клиенте миникарта пишет текст прямо в подсказку, без данных, которых ждал аддон; теперь аддон ловит такие подсказки сам.
- Если подсказки ресурса не было, `/hm tip` показывает последнюю другую подсказку и её владельца.

## 2.0.8

- Minimap tooltips: skill is shown more reliably. The addon now understands more ways the game formats the minimap text (other colour codes, nodes separated by `|n`), and reads the text from the tooltip data when the line itself can't be read.
- If your professions weren't loaded yet when you logged in, the addon now reads them again on the next tooltip instead of waiting for a game event.
- New command `/hm tip`: shows what the last herb or vein tooltip said and why the skill was or wasn't shown.

- Подсказки на миникарте: навык показывается надёжнее. Аддон понимает больше вариантов текста миникарты (другие коды цвета, несколько ресурсов через `|n`) и берёт текст из данных подсказки, если саму строку прочитать нельзя.
- Если при входе в игру профессии ещё не загрузились, аддон перечитает их при следующей подсказке, а не будет ждать события от игры.
- Новая команда `/hm tip`: показывает, что было в последней подсказке травы или жилы и почему навык показан или не показан.

## 2.0.7

- Crabs are no longer shown as skinnable.

Крабы больше не помечаются как «можно снять шкуру».

## 2.0.6

- Spiders are no longer shown as skinnable. They count as beasts in the game, but there is no hide on them.
- Whole families are now learned too: after two different looted corpses of one beast family with no "Skinnable" line, the addon stops offering skinning for that family. One skinnable corpse of the family brings it back.

- Пауки больше не помечаются как «можно снять шкуру». Игра считает их животными, но шкуры с них нет.
- Аддон теперь запоминает целые семейства: если у двух разных обысканных трупов одного семейства нет строки «Можно снять шкуру», снятие шкуры для этого семейства больше не предлагается. Если хоть с одного шкура снимется, семейство снова считается со шкурой.

## 2.0.5

- Achievement pop-up: "HarvestMate Achievement" centred at the top, the achievement name centred below it, the description in a tooltip on hover. The card under the pop-up is gone; the share buttons stay.

Окно достижения: сверху по центру «Достижение HarvestMate», ниже по центру название, описание в подсказке при наведении. Карточка под окном убрана, кнопки «В гильдию» и «В группу» остались.

## 2.0.4

- Achievement pop-up: the shine no longer jumps back to the left edge and stays there after its sweep. It runs across the frame once and disappears.

Окно достижения: блик больше не возвращается к левому краю и не застывает там. Он один раз проходит по окну и исчезает.

## 2.0.3

- Achievement pop-up text: the header and the name always fit (the font shrinks instead of cutting the text off) and sit inside the frame. The full description moved to a small card under the pop-up, next to the share buttons.

Текст в окне достижения: заголовок и название всегда помещаются (шрифт уменьшается, а не обрезается) и стоят внутри рамки. Полное описание перенесено на карточку под окном, рядом с кнопками.

## 2.0.2

- Achievement pop-up: text no longer overlaps the frame, each line stays on one row (hover for the full text), icon and shield are aligned like the game's own achievement alert, share buttons sit right under the frame.
- Achievement sound now plays on the Master channel with fallbacks, and can be turned off in the settings.

- The button in the Bags section is now called "Refresh": it recounts your bags and prices.

Кнопка в разделе «Сумки» теперь называется «Обновить»: она заново пересчитывает сумки и цены.

Окно достижения: текст больше не налезает на рамку, значок и щит выровнены как в игровом окне, кнопки стоят вплотную под окном. Звук достижения играет на общем канале и отключается в настройках.

## 2.0.1

- **Example achievement:** `/hm test` or the "Show an example" button in the Achievements section shows the achievement pop-up with a random achievement. Nothing is earned or saved, and the share buttons only print the message to your own chat.

Пробное достижение: команда `/hm test` или кнопка «Показать пример» в разделе достижений показывает окно достижения. Ничего не выдаётся и не сохраняется, кнопки «В гильдию» и «В группу» только печатают текст сообщения вам в чат.

## 2.0.0

- **Main window** (`/hm` or a click on the minimap button) with sections: Session, Achievements, Records, Bags, What to level, plus a Settings button. Every window now carries the addon name in its title.
- **Achievements:** 25 goals with 90 steps across Herbalism, Mining, Skinning, Lockpicking, one-key gathering, earnings and more. Earning one shows a Wrath-style pop-up with animation and sound, and buttons to share it with your guild or group. You can also share any earned achievement from the list, or have new ones announced to your guild automatically (off by default).
- **Records:** best gold per hour, most valuable session, most gathers in a session, most valuable gather, and lifetime totals. Beating a record shows a pop-up you can share.
- **Share a session summary** to guild or group chat, from the main window or the mini session window.
- Gathering is now recognised even if this version of the game uses different spell IDs: the addon learns the spell from the first gather that yields loot.
- `/hm` now opens the main window; `/hm config` opens the settings.

Главное окно с разделами, достижения (25 целей, 90 ступеней) с всплывающим окном в духе Wrath, рекорды, отправка итога сессии и достижений в чат гильдии или группы. Сбор теперь распознаётся, даже если у заклинаний сбора в этой версии игры другие ID.

## 1.9.1

- Session window: new **What I gathered** button. It opens a panel with your loot as icons (like in bags, most valuable first, with counts and value) and totals per profession: gathers, value and average per gather.
- Bag scans (`/hm bags`, gathering gear, free slots) now include the reagent bag.

В окне сбора за сессию появилась кнопка «Что собрали»: добыча значками, самое дорогое первым, и итоги по каждой профессии. Проверка сумок теперь учитывает сумку для реагентов.

## 1.9.0

- **Session window** (`/hm session` or right-click the minimap button): gathers, value of what you gathered, gold per hour; pause and reset.
- **Average value per gather** in node tooltips, from drop chances and prices.
- **`/hm bags`:** the best way to sell every ore and leather stack in your bags, with a total.
- **Best deal** now checks your skill: options you can't craft yet are greyed out with the skill they need. Bronze (copper + tin) is included.
- Items that sell for less on the auction house than at a vendor are flagged.
- **`/hm next`:** which herbs and veins give skill-ups right now, and what comes next.
- Node tooltips show how many points are left until the next color, and your gear bonus.
- **Auto-loot** is switched on while the gather key is active (optional).
- **Gathering gear:** a reminder when a bonus item is in your bags, or (optional, off by default) equip it at the node and put the old item back afterwards.
- Warning when your bags are almost full.

Окно сбора за сессию с доходом в час, средняя выручка за сбор в подсказке, команда /hm bags для сумок, учёт навыка и бронза в блоке «Что выгоднее», пометка «дешевле торговца», команда /hm next, счётчик до следующего цвета и бонус экипировки в подсказке, автосбор добычи на время сбора, напоминание о вещах с бонусом к сбору и их автоматическая смена, предупреждение о полных сумках.

## 1.8.0

- **Settings reworked.** Sections now go from the main feature down: Node next to you (plate, icon, one-key gathering, key choice, Soft Target Interact button), Professions, Node tooltip, Item tooltip, Reminders, Chat, Other.
- Dependent options are nested under their parent and grey out with it.
- Race and class options (Lockpicking, Find Treasure, Cultivation) are shown only to characters who can use them.
- New buttons: turn on Soft Target Interact, reset settings (with confirmation).
- "Best deal" block is shorter and reads the same in every language: "As is, to a vendor" / "As Tin Bar, on the auction house".
- Wording pass across all 11 languages for consistent terms.

Настройки переработаны: разделы идут от главного (ресурс рядом и сбор одной клавишей) к второстепенному, зависимые настройки вложены в главные, настройки для одной расы или класса видны только им, добавлены кнопки включения мягкой цели и сброса настроек. Блок «Что выгоднее» стал короче. Тексты выверены на всех 11 языках.

## 1.7.3

- The gather key now works for skinning too: walk up to a skinnable corpse and press the key. The plate shows your skinning skill, skill-up ranges and learned drops.

Клавиша сбора теперь работает и для снятия шкур: подошли к трупу зверя и нажали клавишу. На плашке навык снятия шкур, рост навыка и изученная добыча.

## 1.7.2

- While the gather key is active, Click-to-Move is switched on so your character walks up to the node when you press the key. Your own setting is restored when you leave the node. Can be turned off in the settings.

Пока клавиша сбора активна, включается «Перемещение по щелчку мыши»: персонаж сам подходит к ресурсу по нажатию. Когда вы отходите, настройка возвращается. Отключается в настройках.

## 1.7.1

- The gather key and its hint now appear only for nodes you can actually gather: you have the profession and enough skill. Nodes of a profession you don't have are no longer highlighted.

Клавиша сбора и подсказка появляются только у ресурсов, которые вы можете собрать: профессия есть и навыка хватает. Ресурсы чужой профессии больше не подсвечиваются.

## 1.7.0

- **Best deal:** ore, leather scraps and leather tooltips compare selling to a vendor or on the auction house with smelting / combining first and selling the result. Per item, auction prices after the 5% cut, best option highlighted. Auction prices come from Auctionator; without it the addon suggests installing it.

«Что выгоднее»: у руды, обрывков кожи и кожи подсказка сравнивает продажу торговцу и на аукционе с переработкой и продажей результата. Лучший вариант выделен. Цены аукциона — из Auctionator.

## 1.6.2

- Gamepad interface: Soft Target Interact set to "gamepad" now counts as on. HarvestMate no longer tries to change it or reports a false error.
- `/hm near` shows whether the gamepad interface is on.

Интерфейс геймпада: мягкая цель в режиме «для геймпада» теперь считается включённой, аддон больше не пытается её менять и не пишет ложную ошибку. `/hm near` показывает, включён ли геймпад.

## 1.6.1 — first public release

**English**

One-key gathering for WoW Forever.

- **One-key gathering:** walk up to a herb, vein or chest and press one key (F by default). Pick any key or mouse button by pressing it in the settings.
- **Tooltips** on herbs, ore, skinnable beasts and locked chests: your skill vs. the skill needed, colored by difficulty, plus the skill at which the node turns yellow, green and grey.
- **Drops and prices:** what a node gives, with drop chances learned from your own loot; vendor price and auction price (Auctionator or TradeSkillMaster).
- **Nearby highlight:** a bobbing icon above the node in front of you, ringed in its difficulty color, with a small info plate and an optional sound.
- **Item tooltips:** gathering and smelting skill on herbs and ore; lockpicking skill on lockboxes.
- **Reminders:** tracking switched off after death (with a button to turn it back on), Find Treasure for dwarves, trainer ranks ("you can learn the next rank" / "your skill won't grow any more").
- **Cultivation** status for tauren on herb tooltips.
- **Announcements** (optional): a line to your group and an emote when you start gathering.
- **Learns as you play:** new WoW Forever nodes, lower skill requirements, which creatures can be skinned.
- 11 languages: English, Русский, Deutsch, Français, Español, Italiano, Português, 한국어, 简体中文, 繁體中文.
- Commands: `/hm` (settings), `/hm key`, `/hm soft`, `/hm near`, `/hm skills`, `/hm debug`, `/hm reset`, `/hm forget`.

**Русский**

Сбор в одну клавишу для WoW Forever.

- **Сбор в одну клавишу:** подошли к траве, жиле или сундуку и нажали клавишу (по умолчанию F). Клавиша или кнопка мыши выбирается нажатием в настройках.
- **Подсказки** трав, руды, зверей для снятия шкур и запертых сундуков: ваш и нужный навык с цветом по сложности и рост навыка (когда ресурс станет жёлтым, зелёным и серым).
- **Добыча и цены:** что даёт узел, с шансами по вашей добыче; цена у торговца и на аукционе (Auctionator или TradeSkillMaster).
- **Подсветка рядом:** иконка над ресурсом в кольце цвета сложности, плашка с подробностями и звук.
- **Подсказки предметов:** навык сбора и выплавки у травы и руды, навык взлома у сундучков.
- **Напоминания:** поиск выключен после смерти (с кнопкой включения), поиск сокровищ для дворфов, ранги у наставника.
- **Культивация** для тауренов в подсказке травы.
- **Сообщения о сборе** (можно отключить): строка в группу и эмоция.
- **Учится по ходу игры:** новые ресурсы Forever, более низкие требования, с кого можно снять шкуру.
- 11 языков. Команды: `/hm` и другие (см. `/hm help`).

### Fixes before release / Исправления перед релизом

- Nodes are no longer linked to a resource from chest loot; only real gathering counts.
- Skinning messages and learning use the creature you are actually skinning, not the last one you hovered.
- Loot-based node recognition now also works when the game hides the node's name.
- On-screen reminders now really have an outline.
- Protected "turn on" buttons in the tracking reminder no longer cause a Lua error.
- `/hm help` lists `/hm key`.
