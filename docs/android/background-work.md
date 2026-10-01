# Фоновая работа Moru на Android 14–17

## Механизм и декларация Google Play

Активная работа использует одну `GenerationForegroundService` в процессе
приложения и один application-owned FlutterEngine. Выбран `specialUse` с
разрешением `FOREGROUND_SERVICE_SPECIAL_USE` и явным
`android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE`: интерактивная работа
ассистента, streaming, ACP/STDIO, локальные команды, ожидание разрешений и
запущенные пользователем серверы мини-приложений. Тип передаётся Android
только начиная с API 34. Старые устройства используют обычный вызов
`startForeground`. Target SDK и application ID не меняются.

Служба нужна именно для живого выполнения: открытые pipes, subprocesses,
поток ответа и listening server нельзя сохранить deferred job и позже
продолжить с того же байта. Уведомление показывает работу, открывает чат и
позволяет остановить реальные задачи. Partial wake lock принадлежит службе
только при активных владельцах; последний выход/Stop освобождает его.
Ожидание approval входит в активный ход. Cached idle ACP session не является
основанием для бесконечного удержания CPU. `START_NOT_STICKY` не выдаёт
перезапуск пустой службы за восстановление исполнения.

`dataSync` на Android 15+ при соответствующем target SDK ограничен шестью
часами за 24 часа в фоне. В Android 17 исходники `ActiveServices` всё ещё
применяют этот таймер к `dataSync` и `mediaProcessing`, не к `specialUse`.
Выбор `specialUse` обосновывается видом интерактивной работы, а не обходом
квоты. UIDT предназначен для инициированных пользователем сетевых передач;
он не описывает локальный ACP/shell, ожидание разрешения и listening server.
WorkManager с foreground worker также не освобождает от правил FGS.

Google Play проверяет `specialUse`, текст подтипа и видео сценария. Это
инженерное обоснование кандидата, а не подтверждение одобрения. Отдельная
HTTP-генерация без локального runtime пересекается с официальным примером
`dataSync` «data fetch, server-side processing». Её наличие нельзя скрывать
в декларации. При отклонении общего сценария требуется пересмотреть тип
для этого режима; смена ID, повторный запуск службы или другое название
не создают исключения из квоты.

Текст для Play Console должен описывать запуск пользователем Send/Start,
полный смешанный цикл с streaming и локальными инструментами, ущерб от
отложенного старта/прерывания, видимое уведомление и Stop, завершение службы
при отсутствии владельцев. Видео должно показать Home, выключение экрана,
approval и остановку команды/сервера. Не заявлять обещание пережить force-stop
или уже полученное одобрение Play.

## Энергосбережение и пределы защиты

В обычном AOSP Doze активный FGS остаётся foreground для сетевой политики,
а его partial wake lock не отключается как lock обычного фонового процесса.
Исключение из battery optimization не является обязательным условием каждого
запуска на Pixel. `Low Power Standby` — отдельное ограничение: оно может
блокировать сеть и игнорировать wake locks даже у foreground service.
`batteryExempt` не означает `lowPowerStandbyExempt`.

Статус проверяется публичными Android API. Подсказка показывается только
при активной работе и отключённой защите, reported background restriction,
включённом Low Power Standby без exemption, риске Vivo/Xiaomi без allowlist
или предыдущем завершении процесса. Закрытие сохраняется в пользовательских
настройках. Диалоги разрешений и настройки не открываются автоматически.
Battery exception и OEM autostart — действия пользователя; OEM shortcut
имеет fallback, потому что private activity может измениться в прошивке.

FGS не защищает от системного/user Stop, force-stop, нехватки памяти,
thermal/system-health ограничений, Android phantom-process management или
всех действий прошивки Vivo. После гибели процесса сохраняется частичный
ответ, generation run становится interrupted и показывается честное
состояние. Контекст ACP восстанавливается через существующие load/resume;
это не обещает продолжения оборванного prompt. Очередь постоянных чатов
сохраняется атомарно. Старые команды и решения approval не переисполняются.

## Источники

- [FGS types: specialUse](https://developer.android.com/develop/background-work/services/fgs/service-types#special-use)
- [FGS timeout и шестичасовая квота](https://developer.android.com/develop/background-work/services/fgs/timeout)
- [Google Play: foreground-service declarations](https://support.google.com/googleplay/android-developer/answer/13392821?hl=en)
- [UIDT](https://developer.android.com/develop/background-work/background-tasks/uidt)
- [Power-management resource limits](https://developer.android.com/topic/performance/power/power-details)
- [Low Power Standby](https://developer.android.com/reference/android/os/PowerManager#isLowPowerStandbyEnabled())
- [Doze: исключения и допустимые случаи](https://developer.android.com/training/monitoring-device-state/doze-standby#exemption-cases)
- [Android 17 ActiveServices, commit 94b4c163b7dfe5ce3607f7bb8456f9573f7de57d](https://android.googlesource.com/platform/frameworks/base/+/94b4c163b7dfe5ce3607f7bb8456f9573f7de57d/services/core/java/com/android/server/am/ActiveServices.java)

Источники проверены 1 октября 2026 года. Реальная доставка на lock screen,
агрессивное энергосбережение Vivo и system kill требуют устройств; JVM и
Dart-тесты не заменяют эту проверку.
