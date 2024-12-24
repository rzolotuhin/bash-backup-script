## Описание работы

Скрипт производит поиск объектов в файловой системе используя различные шаблоны.<br>
Все правила для поиска описываются в виде списка в самом скрипте.<br>

```bash
list=(
    'правило 1'
    'правило 2'
    # ...
    'правило N'
)
```

Правило поиска может указывать как напрямую на файл или каталог, так и использовать шаблоны в виде регулярных выражений с различными дополнительными параметрами.<br>
Шаблоны позволяют гибко описывать объекты для поиска, что гарантирует попадание в бэкап новых файлов, которые могут появиться в будущем. При этом не потребуется добавлять новые правила для бэкапа.
> Для поиска по регулярным выражениям используется Perl синтаксис.

Скрипт позволяет собирать файлы, используя правила исключения - "все кроме ..."<br>

Несколько примеров смотри [ниже](#примеры-правил-для-бэкапа).

## Используемые каталоги

В процессе работы скрипт использует несколько каталогов.
- `/tmp/backup` - временный каталог, куда складываются копии найденных файлов перед процедурой архивирования. <u><b>Удаляется в процессе!</b></u>
- `/srv/backup` - каталог, в который складываются архивы с собранными бэкапами.

Изменить их расположение можно через переменные `dirBackupTemp` и `dirBackupLocal`.

## Именование архивов с бэкапами
backup_server1_2024.11.16_015333_1db2e580d5df6e4d4554bcc530807813.tar.gz
- `backup` - префикс файла
- `server1` - hostname
- `2024.11.16` - дата %Y.%m.%d
- `015333` - время %H%M%S
- `1db2e580d5df6e4d4554bcc530807813` - контрольная сумма архива, сгенерированная на основании содержимого

Контрольные суммы текущего и последнего сделанного бэкапа сравниваются, в случае их совпадения архив не сохраняется.<br>
Это позволяет избежать создание <u>ПОДРЯД</u> бэкапов с идентичным содержимым, что сэкономит место на диске.

## Список содержимого архива с контрольными суммами
Скрипт добавляет в корень каждого архива бэкапа файл `fingerprint.md5`<br>
Содержимое представляет из себя список контрольных сумм MD5 всех файлов в архиве. Записи отсортированы в алфавитном порядке по полному имени файла, включая путь до него.

```
96b797316b75f50ca482fe0d3e1c61a7  /etc/cron.d/atop
05365d887dba1b3de5f59ee052628b9b  /etc/cron.d/e2scrub_all
e6fa2d74078ac0ac6fd730decf3b3736  /etc/cron.d/php
e5e12910bf011222160404d7bdb824f2  /etc/cron.d/.placeholder
455c3c071b6daabb4e4490828975034c  /etc/cron.d/sysstat
```

Это позволяет быстро искать расхождения между двумя бэкапами через `diff` двух файлов `fingerprint.md5`

## Примеры правил для бэкапа

- Добавить в бэкап каталог<br>
Необходимо указать полный путь до каталога
```bash
/etc/openvpn
```

- Добавить в бэкап файл<br>
Необходимо указать полный путь до файла
```bash
/etc/ntp.conf
```

- Добавить в бэкап несколько файлов имена которых совпадают с регулярным выражением
    - /etc/hostname
    - /etc/hosts
```bash
/etc/<host(name|s)$>
```

- Добавить в бэкап все каталоги c заданиями планировщика задач Cron
```bash
/etc/cron.*
```

- Добавить в бэкап все файлы с расширением `.json` во всех подкаталогах `/root/.docker/`
    - `<\.json$>` - поиск всех файлов `.json`
    - `<R>` - рекурсивно обойти все подкаталоги (структура вложенности сохраняется)
```bash
/root/.docker/<\.json$><R>
```

- Добавить в бэкап все файлы с расширением `.conf` во всех подкаталогах `/etc/nginx/conf.d/`
    - `<\.conf$>` - поиск всех файлов `.conf`
    - `<R>` - рекурсивно обойти все подкаталоги (структура вложенности сохраняется)
```bash
/etc/nginx/conf.d/<\.conf$><R>
```

- Добавить в бэкап всей файлы с расширениями `.cer` и `.key` в корне каталога `/root/.acme.sh/my.domain.net/`
```bash
/root/.acme.sh/my.domain.net/<\.(cer|key)$>
```

- Добавить в бэкап каталоги `.ssh` всех пользователей системы
```bash
/home/*/.ssh
```

- Добавить в бэкап все пользовательские правила udev, исключив из списка файлы, в именах которых есть `test` или `fix`
```bash
/etc/udev/rules.d/<^(?:(?!(test|fix)).)+\.rules$><R>
```

- Добавить в бэкап <u>все файлы</u> кроме тех, что имеют расширение `.tar.gz`, также рекурсивно обойдя все подкаталоги `/srv/my_app_conf/`
    - `<\.tar\.gz$>` - шаблон для сравнения имен файлов
    - `<RI>`
        - `R` - рекурсивно обойти все подкаталоги (структура вложенности сохраняется)
        - `I` - инвертировать логику для поиска по регулярному выражению `<\.tar\.gz$>`
```bash
/srv/my_app_conf/<\.tar\.gz$><RI>
```

## PS
Все правила в скрипте добавлены как пример.
