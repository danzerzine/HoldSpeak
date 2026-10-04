<a id="russian"></a>

<p align="center">
  <img src="docs/screenshots/logo.webp" width="128" alt="Иконка Speak!" />
</p>

<h1 align="center">Speak!</h1>

<p align="center">
  <b>Зажмите клавишу, скажите, отпустите. Текст уже в поле.</b><br />
  Голосовой ввод для Mac по нажатию клавиши. Работает на самом Mac, бесплатно и так быстро, что про него забываешь.
</p>

<p align="center">
  <a href="https://github.com/danzerzine/Speak/releases/latest"><b>Скачать для macOS</b></a>
  &nbsp;·&nbsp; <a href="https://danzerzine.github.io/Speak/ru/">Сайт</a> &nbsp;·&nbsp; macOS 14 и новее &nbsp;·&nbsp; Apple Silicon
  <br /><b>Русский</b> &nbsp;·&nbsp; <a href="#english">English</a>
</p>

<p align="center">
  <img src="docs/screenshots/hero.webp" width="720" alt="Меню Speak! с последними диктовками и плашка записи, пока вы говорите" />
</p>

Говорим мы со скоростью 130–160 слов в минуту, а печатаем 40–60. Если в основном вы пишете промпты для Claude Code, Codex или чата, темп задаёт клавиатура. Speak! это ограничение снимает. Зажмите правый Option, проговорите мысль целиком, отпустите, и текст появится в приложении, где вы сейчас работаете: в терминале, редакторе, комментарии к pull request.

## Быстро, потому что работает на вашем Mac

Речь распознаёт **NVIDIA Parakeet** на самом Mac. На MacBook Air 2020 года с базовым M1 десятисекундная фраза появляется в поле примерно через полсекунды после того, как вы отпустили клавишу. Ничего не уходит в сеть, ни за что не надо платить, интернет не нужен.

- **Русский и английский в одной фразе.** «Сделай rebase на main» так и выходит: `rebase` латиницей, а не «ребейз».
- **Ваши термины запоминаются.** Если название проекта или библиотеки раз за разом выходит с ошибкой, выделите его в любом приложении, нажмите правой кнопкой и выберите **Fix Spelling in Speak!**. Впишите правильное написание один раз, и дальше оно будет выходить верно.
- **Буфер обмена не трогается.** Текст печатается прямо в поле, поэтому в буфере остаётся то, что вы туда положили. Поля паролей Speak! пропускает и ничего из них не сохраняет.
- **Диктовки не теряются.** Если текст не удалось вставить, он ждёт в меню, и его можно скопировать одним нажатием. Если не сработало распознавание, запись сохраняется, и в меню появляется **Retry**.

## Что вы видите

**Пока вы говорите**, небольшая плашка показывает текущую громкость голоса и время. Она висит под значком в строке меню или внизу экрана, стеклянная или того цвета, который вы выберете. **Когда всё готово**, значок коротко вздрагивает, а текст уже на месте. Никаких окон и всплывающих уведомлений.

**Значок в строке меню показывает состояние ещё до того, как вы заговорите**: готов, слушает, распознаёт, загружает модель или ему не хватает разрешения. В меню видны движок, последние диктовки и сколько вы надиктовали за сегодня.

**Первый запуск — четыре коротких шага**: что умеет приложение, где распознавать речь, три разрешения macOS (они проверяются сами, без кнопок «проверить ещё раз») и поле, где можно попробовать первую диктовку. Пока вы выдаёте разрешения, скачивается модель.

**Настройки** устроены как «Системные настройки»: боковая панель с разделами General, Shortcut, Recognition, Dictionary и History.

## Установка

1. Скачайте DMG со страницы [версий](https://github.com/danzerzine/Speak/releases/latest), откройте его и перетащите **Speak.app** в «Программы».
2. Приложение подписано автором, но не нотаризовано Apple, поэтому macOS блокирует первый запуск. Откройте «Системные настройки» → «Конфиденциальность и безопасность», найдите сообщение о том, что Speak заблокирован, и нажмите «Всё равно открыть».
3. Дальше ведёт окно приветствия. Speak! нужны три разрешения:
   - **Микрофон** — чтобы слышать вас, пока клавиша зажата;
   - **Универсальный доступ** — чтобы печатать текст в приложение, где вы работаете;
   - **Мониторинг ввода** — чтобы замечать, что вы зажали горячую клавишу.

Speak! живёт в строке меню (значок рации), в Dock его нет.

**Обновления.** Раз в день Speak! проверяет, не вышла ли новая версия. Если вышла, в меню появляется плашка: нажмите **Install…**, потом **Install Update**, и приложение само скачает обновление, проверит подпись, заменит себя и перезапустится. Проверить вручную можно в Settings → General → Updates → **Check Now**. Версии до 0.3.3 обновляться сами не умеют: один раз установите 0.3.3 из DMG. Настройки, история, словари и модели лежат в `~/Library/Application Support/Speak/` и при обновлении сохраняются.

**Если у вас был HoldSpeak.** Speak! — то же приложение под новым именем. При первом запуске оно перенесёт модели, историю и словари и сохранит настройки. Для macOS это новое приложение, поэтому три разрешения придётся выдать ещё раз (окно приветствия откроется сразу на этом шаге). Потом удалите `HoldSpeak.app`.

## Как пользоваться

1. Зажмите **правый Option** (или **правый Command**, вторую горячую клавишу). Обе меняются в Settings → Shortcut, вторую можно отключить.
2. Говорите.
3. Отпустите. Текст напечатается в активном поле.

Нажатия короче 150 мс не считаются. Не считается и нажатие, во время которого вы нажали другую клавишу, так что сочетания с ⌥ работают как раньше. Через пять минут запись останавливается сама; этот предел меняется в Settings → Shortcut.

## Движки распознавания

| Движок | Где работает | Размер | Для чего |
|---|---|---|---|
| **Parakeet Ultra** (по умолчанию) | На вашем Mac | 610 МБ | Скорость. Русский и английский, без интернета |
| Whisper Tiny / Small / Turbo | На вашем Mac | 75 МБ – 1,5 ГБ | Языки, которых нет в Parakeet; Turbo — лучшее качество Whisper |
| Gemini 3.5 Transcribe / Flash-Lite | Облако Google, ваш ключ API | — | Речь, где языки сильно перемешаны |

Движок переключается в Settings → Recognition. Модели Whisper, которые уже скачал MacWhisper или другое приложение на WhisperKit, Speak! найдёт и использует.

**Gemini — по желанию.** Создайте ключ в [Google AI Studio](https://aistudio.google.com/apikey) и включите оплату для его проекта: бесплатный тариф заканчивается после пары десятков диктовок в день. Speak! проверяет ключ у Google и хранит его в связке ключей macOS. С Gemini звук каждой диктовки уходит в Google; локальные движки ничего никуда не отправляют.

## Словарь

Модели распознавания знают обычные слова и спотыкаются на IT-терминах: `пулл реквест` вместо *pull request*, `кубернетес` вместо *Kubernetes*. Словарь сопоставляет услышанное с тем, что вы имели в виду, отдельно для каждого языка, и исправляет текст до того, как он напечатается. В комплекте около 110 терминов для русского и 120 для английского: git, языки программирования, фронтенд, бэкенд, данные, DevOps, облака и инструменты ИИ.

С Parakeet словарь работает ещё и по звучанию: небольшая дополнительная модель (98 МБ) ловит слова, которые *звучат как* один из ваших терминов, так что `пул реквист` всё равно становится *pull request*, даже если именно такой ошибки в списке нет.

Чтобы добавить термин, откройте Settings → Dictionary и заполните строку, которая там всегда открыта: **Transcribed as** `бойскап` → **Should be** `Basecamp`, Return. Или выделите неверное слово в любом приложении и выберите **Fix Spelling in Speak!** в контекстном меню. Словари — это обычные JSON-файлы в `~/Library/Application Support/Speak/terminology/`: их можно импортировать, экспортировать и хранить вместе с dotfiles.

## Если что-то не работает

- **Горячая клавиша ничего не делает.** Проверьте «Универсальный доступ» и «Мониторинг ввода» в «Системных настройках» → «Конфиденциальность и безопасность». Пока разрешения не хватает, на значке в строке меню горит оранжевая метка.
- **Пустой результат.** Проверьте уровень входного сигнала в «Системных настройках» → «Звук» → «Вход» и микрофон, выбранный в Settings → Recognition.
- **Журнал** лежит в `~/Library/Logs/Speak.log`:

```bash
tail -f ~/Library/Logs/Speak.log
```

## Сборка из исходников

Нужны Xcode 26 и [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
./scripts/rebuild.sh
```

Скрипт генерирует проект, собирает Release, устанавливает его в `/Applications` и подписывает. Один раз запустите `scripts/setup-signing.sh`, чтобы macOS сохраняла разрешения между пересборками. `scripts/readme-screenshots.sh` заново снимает картинку в начале этой страницы на демонстрационных данных.

## Откуда взялся Speak!

Speak! начинался как форк [timmal/HoldSpeak](https://github.com/timmal/HoldSpeak) и сохранил его главную идею. В него добавлены движок Parakeet, словарь исправлений со службой Fix Spelling, Gemini и новый интерфейс.

<br />

---

<a id="english"></a>

<h1 align="center">Speak! in English</h1>

<p align="center">
  <b>Hold a key, talk, let go. The text is already in the field.</b><br />
  Push-to-talk dictation for the Mac menu bar. Local, free, and fast enough to forget it's there.
</p>

<p align="center">
  <a href="https://github.com/danzerzine/Speak/releases/latest"><b>Download for macOS</b></a>
  &nbsp;·&nbsp; <a href="https://danzerzine.github.io/Speak/">Website</a> &nbsp;·&nbsp; macOS 14 or later &nbsp;·&nbsp; Apple Silicon
  <br /><a href="#russian">Русский</a> &nbsp;·&nbsp; <b>English</b>
</p>


People speak at 130–160 words a minute and type at 40–60. When most of your work is writing prompts for Claude Code, Codex or a chat window, typing speed becomes the limit on how fast you can iterate. Speak! removes it. Hold Right Option, say the whole thought, release, and the text lands in whatever app has focus: a terminal, an editor, a pull request comment.

## Fast because it runs on your Mac

Speech is recognized by **NVIDIA Parakeet** on the Mac itself. On a 2020 MacBook Air with the base M1, a ten-second phrase appears in the field about half a second after you let go of the key. Nothing is uploaded, nothing is billed, and it works offline.

- **Russian and English in one sentence.** "Сделай rebase на main" comes out with `rebase` spelled the way you write it, not transliterated.
- **Your vocabulary, learned once.** If a project name or a library keeps coming out wrong, select it anywhere, right-click, and pick **Fix Spelling in Speak!**. Type the right spelling once and every later dictation gets it right.
- **No clipboard games.** Text is typed straight into the focused field, so your clipboard stays as you left it. Password fields are skipped, and nothing typed into them is saved.
- **Never loses a dictation.** If the text can't be inserted, it's waiting in the menu, one click from the clipboard. If recognition fails, the audio is kept and the menu offers **Retry**.

## What you see

**While you talk**, a small pill shows the live voice level and the time. It sits under the menu bar icon or at the bottom of the screen, in glass or a colour you choose. **When it's done**, the icon pops and the text is in place. No windows open and no toasts appear.

**The menu bar icon tells you the state before you speak**: ready, listening, transcribing, a model loading, or a permission missing. The menu shows the engine, your last dictations, and how much you dictated today.

**First launch takes four short steps**: what the app does, where to recognize speech, three macOS permissions (checked automatically, no "Re-check" buttons), and a practice field to try your first dictation. The model downloads while you grant permissions.

**Settings** follow System Settings: a sidebar with General, Shortcut, Recognition, Dictionary and History.

## Install

1. Download the DMG from [Releases](https://github.com/danzerzine/Speak/releases/latest), open it and drag **Speak.app** into Applications.
2. The app is self-signed, so macOS blocks the first launch. Open **System Settings → Privacy & Security**, find *"Speak was blocked…"* and click **Open Anyway**.
3. Follow the welcome window. Speak! needs three permissions:
   - **Microphone**, to hear you while you hold the key;
   - **Accessibility**, to type the text into the app you're using;
   - **Input Monitoring**, to notice when you hold the hotkey.

Speak! lives in the menu bar (the walkie-talkie icon) and has no Dock icon.

**Updates.** Speak! checks for a new version once a day. When one is out, the menu shows a banner: click **Install…**, then **Install Update**, and the app downloads it, checks its signature, replaces itself and restarts. Settings → General → Updates → **Check Now** checks by hand. Versions before 0.3.3 can't update themselves: install 0.3.3 from the DMG once. Settings, history, dictionaries and models live in `~/Library/Application Support/Speak/` and survive updates.

**Coming from HoldSpeak.** Speak! is the same app under a new name. On first launch it moves your models, history and dictionaries over and keeps your preferences. macOS sees it as a new app, so grant the three permissions once more (the welcome window opens on that step) and delete `HoldSpeak.app`.

## Use

1. Hold **Right Option** (or **Right Command**, the second hotkey). Either can be changed in Settings → Shortcut, and the second can be turned off.
2. Speak.
3. Release. The text is typed into the focused field.

Presses shorter than 150 ms are ignored, and so is a hold during which you press another key, so ⌥-shortcuts keep working. Recording stops on its own after five minutes; the limit is in Settings → Shortcut.

## Recognition engines

| Engine | Where it runs | Size | Good for |
|---|---|---|---|
| **Parakeet Ultra** (default) | On your Mac | 610 MB | Speed. Russian and English, offline |
| Whisper Tiny / Small / Turbo | On your Mac | 75 MB – 1.5 GB | Languages Parakeet lacks; Turbo for the best Whisper quality |
| Gemini 3.5 Transcribe / Flash-Lite | Google cloud, your API key | — | Heavily mixed-language speech |

Switch engines in Settings → Recognition. Whisper models already downloaded by MacWhisper or another WhisperKit app are found and reused.

**Gemini is optional.** Create a key in [Google AI Studio](https://aistudio.google.com/apikey) and turn on billing for its project: the free tier stops after a couple dozen dictations a day. The key is checked with Google and stored in the macOS Keychain. With Gemini, each dictation's audio goes to Google; the local engines never send anything anywhere.

## Dictionary

Speech models know everyday words and stumble on IT terms: `пулл реквест` instead of *pull request*, `кубернетес` instead of *Kubernetes*. The dictionary maps what was heard to what you meant, per language, and fixes the text before it is typed. It ships with about 110 terms for Russian and 120 for English, covering git, languages, frontend, backend, data, DevOps, cloud and AI tools.

With Parakeet the dictionary also works by sound: a small extra model (98 MB) catches words that *sound like* one of your terms, so `пул реквист` still becomes *pull request* even if that exact misspelling isn't in the list.

To add a term, open Settings → Dictionary and fill the always-open row: **Transcribed as** `бойскап` → **Should be** `Basecamp`, Return. Or select the wrong word in any app and choose **Fix Spelling in Speak!** from the context menu. Dictionaries are plain JSON in `~/Library/Application Support/Speak/terminology/` and can be imported, exported and kept in your dotfiles.

## Troubleshooting

- **The hotkey does nothing.** Check Accessibility and Input Monitoring in System Settings → Privacy & Security. The menu bar icon shows an orange badge while a permission is missing.
- **Empty results.** Check the input level in System Settings → Sound → Input, and the microphone chosen in Settings → Recognition.
- **Logs** are in `~/Library/Logs/Speak.log`:

```bash
tail -f ~/Library/Logs/Speak.log
```

## Build from source

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
./scripts/rebuild.sh
```

It generates the project, builds a Release copy, installs it to `/Applications` and signs it. Run `scripts/setup-signing.sh` once so macOS keeps the permissions across rebuilds. `scripts/readme-screenshots.sh` regenerates the image at the top of this page from demo data.

## About this fork

Speak! started as a fork of [timmal/HoldSpeak](https://github.com/timmal/HoldSpeak) and keeps its core idea. It adds the Parakeet engine, the correction dictionary with the Fix Spelling service, Gemini, and a new interface.
