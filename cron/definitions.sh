#!/bin/bash
# ==========================================================
# CronJobs-Proxmox - Definition aller automatischen Aufgaben
# ==========================================================
# Kategorien und Job-Definitionen. Enthaelt keine Logik,
# nur Daten und die Helfer zum Auslesen der Felder.
# ==========================================================

# ================================================================
# KATEGORIEN (Zugehoerigkeitsnamen)
# ================================================================
# Format: Kuerzel|Kurzname (Menue)|Beschreibung (Untermenue)

CATEGORIES=(
"sicherung|Sicherung|Backups von VMs und Containern erstellen, pruefen und aufraeumen"
"snapshots|Momentaufnahmen|Snapshots erstellen und alte automatisch aufraeumen"
"speicher|Speicher und ZFS|Festplatten, ZFS-Pools und freier Speicherplatz"
"wartung|System-Wartung|Updates, Kernel, Protokolle und Aufraeumarbeiten"
"sicherheit|Sicherheit|Zertifikate, Anmeldeversuche und Sicherheitsupdates"
"cluster|Cluster und HA|Quorum, Hochverfuegbarkeit und Replikation"
"netzwerk|Netzwerk|Verbindungen, Namensaufloesung und Freigaben"
"konfiguration|Konfiguration|Einstellungen sichern und regelmaessige Berichte"
)

cat_field() {
    echo "$1" | awk -F'|' -v f="$2" '{print $f}'
}

# ================================================================
# CRON-JOB-DEFINITIONEN
# ================================================================
# Format: ID|Kategorie|Skriptname|Kurzbeschreibung|Zeitplan-Klartext|Ausfuehrliche Erklaerung

CRON_JOB_DEFS=(
# ---------- Sicherung ----------
"sicherung-alle-taeglich|sicherung|backup-alle-vms-und-container.sh|Sichert taeglich ALLE VMs und Container|Taeglich 02:00 Uhr|Erstellt jede Nacht eine vollstaendige Sicherung von allen virtuellen Maschinen und allen Containern auf diesem Server. Verwendet den Snapshot-Modus, damit die Systeme dabei weiterlaufen koennen (kein Ausschalten noetig). Die Sicherungen landen auf dem Speicher, den du beim ersten Aktivieren auswaehlst. Das ist der wichtigste Job ueberhaupt - ohne Backup ist alles weg, wenn eine Festplatte stirbt."
"sicherung-nur-vms-taeglich|sicherung|backup-nur-vms.sh|Sichert taeglich nur die virtuellen Maschinen|Taeglich 02:30 Uhr|Sichert ausschliesslich die virtuellen Maschinen (VMs, z.B. Windows oder Linux mit eigenem Kernel), keine Container. Sinnvoll, wenn du VMs und Container zu unterschiedlichen Zeiten sichern willst, damit sie sich nicht gegenseitig ausbremsen."
"sicherung-nur-container-taeglich|sicherung|backup-nur-container.sh|Sichert taeglich nur die LXC-Container|Taeglich 03:00 Uhr|Sichert ausschliesslich die LXC-Container (die leichtgewichtigen Systeme, die sich den Kernel mit dem Host teilen). Container sind meist deutlich kleiner und schneller gesichert als VMs."
"sicherung-alte-loeschen-woechentlich|sicherung|backup-alte-loeschen.sh|Loescht alte Sicherungen automatisch|Sonntags 04:00 Uhr|Ohne Aufraeumen laeuft die Backup-Festplatte irgendwann voll und dann schlagen ALLE neuen Sicherungen fehl. Dieser Job loescht Sicherungsdateien, die aelter als eine von dir festgelegte Anzahl Tage sind (Standard 30 Tage). Du wirst beim Aktivieren nach der Aufbewahrungsdauer gefragt."
"sicherung-pruefen-woechentlich|sicherung|backup-integritaet-pruefen.sh|Prueft ob die Sicherungen lesbar sind|Sonntags 05:00 Uhr|Eine kaputte Sicherungsdatei merkt man normalerweise erst im Notfall - also genau dann, wenn es zu spaet ist. Dieser Job oeffnet jede Sicherungsdatei testweise und prueft, ob sie fehlerfrei lesbar ist. Ergebnisse stehen im Log."
"sicherung-bericht-woechentlich|sicherung|backup-wochenbericht.sh|Schreibt eine Uebersicht aller Sicherungen|Montags 07:00 Uhr|Erstellt jede Woche eine uebersichtliche Zusammenfassung: welche Sicherungen existieren, wie alt sie sind, wie viel Platz sie belegen und ob eine VM oder ein Container seit laengerem gar nicht mehr gesichert wurde. Gut, um regelmaessig einen Blick darauf zu werfen."
"sicherung-testrestore-erinnerung-monatlich|sicherung|backup-testwiederherstellung-erinnerung.sh|Erinnert monatlich an einen Test-Restore|Am 1. des Monats, 08:00 Uhr|Merksatz aus der Praxis: Eine Sicherung, die nie zurueckgespielt wurde, ist keine Sicherung. Dieser Job schreibt einmal im Monat eine Erinnerung ins Log und ins System-Journal, dass du eine beliebige VM testweise wiederherstellen solltest. Er stellt selbst nichts wieder her - er erinnert nur."

# ---------- Snapshots ----------
"snapshot-erstellen-taeglich|snapshots|snapshot-taeglich-erstellen.sh|Erstellt taeglich Momentaufnahmen|Taeglich 04:30 Uhr|Erstellt von allen laufenden VMs und Containern eine Momentaufnahme (Snapshot) mit dem Namen auto-JJJJMMTT. Damit kannst du innerhalb von Sekunden auf den Stand von gestern zurueck, falls ein Update oder eine Aenderung schiefgeht. Achtung: Snapshots sind KEIN Ersatz fuer Backups, da sie auf derselben Festplatte liegen."
"snapshot-aufraeumen-taeglich|snapshots|snapshot-alte-aufraeumen.sh|Loescht alte automatische Momentaufnahmen|Taeglich 05:30 Uhr|Alte Snapshots fressen Speicherplatz und bremsen mit der Zeit das System aus. Dieser Job loescht nur Snapshots mit einem bestimmten Namensanfang (Standard auto-), die aelter sind als eine von dir gewaehlte Zahl von Tagen. Von Hand angelegte Snapshots ohne diesen Namensanfang bleiben garantiert unangetastet."
"snapshot-zfs-aufraeumen-taeglich|snapshots|zfs-snapshots-aufraeumen.sh|Loescht alte ZFS-Snapshots auf Dateisystemebene|Taeglich 05:45 Uhr|Neben den Proxmox-Snapshots legt auch ZFS selbst Momentaufnahmen an, zum Beispiel bei Replikation oder wenn ein Snapshot mal nicht sauber aufgeraeumt wurde. Dieser Job listet solche verwaisten ZFS-Snapshots auf und loescht die, die aelter sind als die eingestellte Frist."
"snapshot-anzahl-warnung-taeglich|snapshots|snapshot-anzahl-warnung.sh|Warnt bei zu vielen Momentaufnahmen|Taeglich 09:00 Uhr|Wenn eine VM oder ein Container sehr viele Snapshots angesammelt hat, wird sie langsam und der Speicherplatz laeuft schleichend voll. Dieser Job zaehlt die Snapshots pro System und schreibt eine Warnung ins Log, wenn eine Grenze ueberschritten wird."

# ---------- Speicher und ZFS ----------
"zfs-scrub-monatlich|speicher|zfs-scrub-datenpruefung.sh|Prueft monatlich alle Daten auf Fehler|Erster Sonntag im Monat, 02:00 Uhr|Ein Scrub liest jeden einzelnen gespeicherten Datenblock und vergleicht ihn mit seiner Pruefsumme. Stille Datenfehler (Bitrot) werden dabei erkannt und bei gespiegelten Platten automatisch repariert. Der Scrub laeuft im Hintergrund weiter und macht das System waehrenddessen etwas langsamer - deshalb nachts. Empfehlung: einmal pro Monat."
"zfs-pool-status-taeglich|speicher|zfs-pool-gesundheit-pruefen.sh|Prueft taeglich den Zustand der ZFS-Pools|Taeglich 06:30 Uhr|Meldet, wenn ein ZFS-Pool nicht mehr im Zustand ONLINE ist, also zum Beispiel eine Festplatte ausgefallen ist (DEGRADED) oder Lese-/Schreibfehler aufgetreten sind. So bemerkst du einen Plattenausfall am naechsten Tag statt erst dann, wenn auch die zweite Platte stirbt."
"zfs-trim-monatlich|speicher|zfs-trim-ssd.sh|Haelt SSDs schnell (TRIM)|Erster Samstag im Monat, 03:00 Uhr|Teilt der SSD mit, welche Speicherbereiche nicht mehr benoetigt werden. Ohne TRIM werden SSDs mit der Zeit spuerbar langsamer. Bei normalen Festplatten (HDD) hat der Job keine Wirkung und schadet auch nicht."
"zfs-arc-bericht-woechentlich|speicher|zfs-arc-speicher-bericht.sh|Berichtet ueber den ZFS-Arbeitsspeicherverbrauch|Sonntags 08:00 Uhr|ZFS nutzt einen Teil des Arbeitsspeichers als Cache (ARC). Wenn der zu gross wird, bleibt zu wenig RAM fuer die VMs uebrig. Dieser Bericht zeigt, wie viel Speicher ZFS gerade belegt und wie gut der Cache arbeitet."
"speicherplatz-warnung-taeglich|speicher|speicherplatz-warnung.sh|Warnt wenn eine Festplatte voll wird|Taeglich 08:00 Uhr|Wenn die System-Festplatte vollaeuft, geht bei Proxmox sehr schnell gar nichts mehr: die Weboberflaeche zeigt Fehler, VMs starten nicht und die Konfiguration wird schreibgeschuetzt. Dieser Job prueft alle Laufwerke und schreibt eine Warnung, sobald eines ueber 90 Prozent voll ist."
"lvm-thin-pruefen-taeglich|speicher|lvm-thin-pool-pruefen.sh|Prueft LVM-Thin-Speicher auf Ueberfuellung|Taeglich 08:15 Uhr|Wer LVM-Thin statt ZFS nutzt, hat ein zusaetzliches Risiko: Der Thin-Pool kann voll laufen, obwohl scheinbar noch Platz da ist - und dann werden VM-Festplatten schreibgeschuetzt oder beschaedigt. Der Job prueft Daten- und Metadaten-Fuellstand und warnt rechtzeitig."
"verwaiste-datentraeger-woechentlich|speicher|verwaiste-datentraeger-suchen.sh|Findet Festplatten geloeschter VMs|Samstags 09:00 Uhr|Wenn eine VM oder ein Container geloescht wird, bleibt manchmal die virtuelle Festplatte auf dem Speicher zurueck und belegt weiter Platz. Dieser Job sucht solche verwaisten Datentraeger und listet sie im Log auf. Geloescht wird nichts automatisch - das musst du bewusst selbst tun."
"speicher-status-taeglich|speicher|speicher-status-pruefen.sh|Prueft ob alle Speicher erreichbar sind|Taeglich 07:30 Uhr|Wenn ein Netzwerkspeicher (NFS, CIFS, iSCSI) nicht erreichbar ist, starten die darauf liegenden VMs nicht mehr und Sicherungen schlagen fehl. Der Job prueft den Status aller eingebundenen Speicher und meldet alle, die als inaktiv gemeldet werden."

# ---------- Wartung ----------
"updates-pruefen-woechentlich|wartung|updates-pruefen.sh|Prueft ob Updates verfuegbar sind|Montags 06:00 Uhr|Prueft, ob es neue Pakete gibt, und schreibt die Liste ins Log. Es wird bewusst NICHTS installiert - Updates auf einem Virtualisierungsserver sollte man immer bewusst und zu einem passenden Zeitpunkt einspielen, nicht automatisch mitten im Betrieb."
"sicherheitsupdates-pruefen-taeglich|wartung|sicherheitsupdates-pruefen.sh|Meldet taeglich verfuegbare Sicherheitsupdates|Taeglich 06:15 Uhr|Wie die Update-Pruefung, aber nur fuer sicherheitsrelevante Aktualisierungen. Diese sollte man deutlich schneller einspielen als normale Updates. Auch hier wird nichts automatisch installiert."
"smart-pruefen-taeglich|wartung|festplatten-smart-pruefen.sh|Prueft taeglich die Festplatten-Gesundheit|Taeglich 06:00 Uhr|Jede moderne Festplatte und SSD fuehrt selbst Buch ueber ihren Zustand (SMART-Werte). Der Job liest diese Werte aus und warnt, wenn eine Platte Fehler meldet oder bereits Sektoren ausgefallen sind. Damit hast du meist Wochen Vorwarnzeit vor einem Ausfall."
"kernel-neustart-pruefen-taeglich|wartung|kernel-neustart-pruefen.sh|Meldet wenn ein Neustart noetig ist|Taeglich 07:00 Uhr|Nach einem Kernel-Update laeuft der Server noch mit dem alten Kernel, bis er neu gestartet wird. Dieser Job vergleicht laufenden und installierten Kernel und meldet, wenn ein Neustart faellig ist. Neu gestartet wird natuerlich nichts automatisch."
"logs-aufraeumen-woechentlich|wartung|logs-aufraeumen.sh|Begrenzt die Groesse der System-Logs|Sonntags 03:00 Uhr|Die System-Protokolle (journald) koennen unbemerkt mehrere Gigabyte belegen und so die Systemplatte fuellen. Der Job begrenzt sie auf eine feste Groesse (Standard 500 MB) und loescht die aeltesten Eintraege."
"paketcache-leeren-woechentlich|wartung|paketcache-leeren.sh|Loescht heruntergeladene Installationsdateien|Sonntags 03:30 Uhr|Beim Installieren von Updates werden die Paketdateien heruntergeladen und danach nicht mehr gebraucht - sie bleiben aber liegen. Der Job raeumt diesen Zwischenspeicher auf und gibt so oft mehrere hundert Megabyte frei."
"alte-kernel-entfernen-monatlich|wartung|alte-kernel-entfernen.sh|Entfernt nicht mehr benoetigte alte Kernel|Am 5. des Monats, 04:00 Uhr|Bei jedem Update kommt ein neuer Kernel dazu, die alten bleiben liegen. Auf der kleinen Boot-Partition fuehrt das irgendwann zu Fehlern beim Update. Der Job entfernt alte, nicht mehr benoetigte Kernel und behaelt den aktuellen sowie einen Ersatz-Kernel."
"temp-aufraeumen-woechentlich|wartung|temp-dateien-aufraeumen.sh|Raeumt alte temporaere Dateien auf|Samstags 04:30 Uhr|Loescht Dateien in den Temporaer-Verzeichnissen, die aelter als 7 Tage und groesser als 10 MB sind. Das sind fast immer Reste abgebrochener Vorgaenge, die niemand mehr braucht."
"dienste-ueberwachen-alle-15min|wartung|pve-dienste-ueberwachen.sh|Startet abgestuerzte Proxmox-Dienste neu|Alle 15 Minuten|Prueft, ob die wichtigen Proxmox-Dienste laufen (unter anderem der Dienst hinter der Weboberflaeche). Falls einer abgestuerzt ist, wird er automatisch neu gestartet und der Vorfall ins Log geschrieben. Damit ist die Weboberflaeche nach einem Absturz spaetestens nach 15 Minuten wieder da."

# ---------- Sicherheit ----------
"ssl-zertifikat-erneuern-taeglich|sicherheit|ssl-zertifikat-erneuern.sh|Erneuert das HTTPS-Zertifikat automatisch|Taeglich 03:00 Uhr|Wenn du ein Let's-Encrypt-Zertifikat nutzt, laeuft es alle 90 Tage ab und der Browser zeigt dann eine Warnung. Proxmox erneuert normalerweise selbst - dieser Job ist ein Sicherheitsnetz, das taeglich prueft und bei Bedarf erneuert. Ohne Let's Encrypt passiert einfach nichts."
"anmeldungen-pruefen-taeglich|sicherheit|anmeldungen-pruefen.sh|Meldet fehlgeschlagene Anmeldeversuche|Taeglich 07:45 Uhr|Zaehlt die fehlgeschlagenen Anmeldeversuche des letzten Tages (SSH und Weboberflaeche). Viele Fehlversuche von derselben Adresse deuten auf einen Angriffsversuch hin - dann solltest du den Zugang von aussen einschraenken."
"firewall-status-woechentlich|sicherheit|firewall-status-pruefen.sh|Prueft ob die Firewall aktiv ist|Montags 07:15 Uhr|Schreibt woechentlich in das Log, ob die Proxmox-Firewall eingeschaltet ist und welche Regeln aktiv sind. Praktisch, um zu bemerken, wenn die Firewall bei einer Fehlersuche mal abgeschaltet und dann vergessen wurde."
"zeitsynchronisierung-pruefen-taeglich|sicherheit|zeitsynchronisierung-pruefen.sh|Prueft ob die Systemuhr richtig geht|Taeglich 06:45 Uhr|Eine falsch gehende Uhr sorgt fuer erstaunlich viele Probleme: Zertifikate gelten als ungueltig, im Cluster streiten sich die Server, Sicherungen bekommen falsche Zeitstempel. Der Job prueft, ob die Zeitsynchronisierung laeuft und die Abweichung klein ist."
"benutzer-audit-monatlich|sicherheit|benutzerkonten-pruefen.sh|Listet monatlich alle Benutzer und Tokens|Am 1. des Monats, 09:00 Uhr|Schreibt eine Uebersicht aller Proxmox-Benutzerkonten, Gruppen und API-Tokens ins Log. So faellt auf, wenn ein altes Konto oder ein vergessener Zugangstoken noch existiert, den niemand mehr braucht."

# ---------- Cluster ----------
"cluster-quorum-pruefen-stuendlich|cluster|cluster-quorum-pruefen.sh|Prueft ob der Cluster beschlussfaehig ist|Jede Stunde|Nur wenn genug Server im Cluster erreichbar sind, darf Proxmox Aenderungen speichern. Faellt das weg (Quorum verloren), wird die Konfiguration schreibgeschuetzt und VMs lassen sich nicht mehr starten. Dieser Job erkennt den Zustand frueh und schreibt eine Warnung. Auf einem Einzelserver ohne Cluster meldet er einfach nichts."
"ha-status-pruefen-taeglich|cluster|ha-status-pruefen.sh|Prueft die Hochverfuegbarkeits-Dienste|Taeglich 07:15 Uhr|Prueft, ob alle als hochverfuegbar markierten VMs und Container im erwarteten Zustand sind, und meldet Fehlerzustaende wie fence oder error. Ohne konfigurierte HA passiert nichts."
"cluster-netzwerk-pruefen-taeglich|cluster|cluster-netzwerk-pruefen.sh|Prueft die Cluster-Verbindungen|Taeglich 07:20 Uhr|Die Server im Cluster halten ueber ein eigenes Netzwerk (Corosync) staendig Kontakt. Wackelt diese Verbindung, kommt es zu unerklaerlichen Aussetzern und im schlimmsten Fall zu automatischen Neustarts. Der Job prueft die Verbindungsqualitaet aller Links."
"replikation-pruefen-taeglich|cluster|replikation-status-pruefen.sh|Prueft ob die Replikation funktioniert|Taeglich 07:25 Uhr|Wenn VMs per ZFS-Replikation auf einen zweiten Server gespiegelt werden, muss das auch tatsaechlich klappen. Der Job meldet Replikationsauftraege, die Fehler haben oder seit langem nicht mehr erfolgreich gelaufen sind."

# ---------- Netzwerk ----------
"internetverbindung-pruefen-alle-30min|netzwerk|internetverbindung-pruefen.sh|Prueft regelmaessig die Netzwerkverbindung|Alle 30 Minuten|Prueft, ob das Standard-Gateway und ein Server im Internet erreichbar sind, und schreibt Ausfaelle mit Uhrzeit ins Log. So kannst du spaeter nachvollziehen, ob eine Stoerung am Server oder an der Internetleitung lag."
"dns-pruefen-taeglich|netzwerk|dns-aufloesung-pruefen.sh|Prueft ob Namensaufloesung funktioniert|Taeglich 06:20 Uhr|Wenn die Namensaufloesung (DNS) nicht geht, schlagen Updates fehl, Zertifikate lassen sich nicht erneuern und im Cluster finden sich die Server nicht mehr. Der Job testet das taeglich und meldet Probleme frueh."
"freigaben-neu-verbinden-alle-5min|netzwerk|netzwerkfreigaben-neu-verbinden.sh|Verbindet abgerissene Netzwerkfreigaben neu|Alle 5 Minuten|Wenn ein Netzwerkspeicher (NAS) kurz nicht erreichbar war, bleibt die Verbindung manchmal haengen, auch wenn das NAS laengst wieder da ist. Der Job prueft alle eingebundenen Freigaben und verbindet sie bei Bedarf automatisch neu."

# ---------- Konfiguration und Berichte ----------
"konfiguration-sichern-taeglich|konfiguration|proxmox-konfiguration-sichern.sh|Sichert taeglich die Proxmox-Einstellungen|Taeglich 01:00 Uhr|Sichert die Konfigurationsdateien von Proxmox (Speicher-Definitionen, Netzwerk-Einstellungen, Benutzer, VM-Konfigurationen) in ein kleines Archiv. Falls du dich mal aussperrst oder eine Einstellung zerschiesst, kannst du damit den vorherigen Stand nachschauen oder zurueckspielen. Aufbewahrung: 14 Tage."
"vorlagen-aktualisieren-woechentlich|konfiguration|container-vorlagen-aktualisieren.sh|Haelt die Container-Vorlagen aktuell|Montags 05:00 Uhr|Aktualisiert die Liste der herunterladbaren Container-Vorlagen (Debian, Ubuntu, Alpine und so weiter). Ohne das bekommst du beim Anlegen eines neuen Containers nur veraltete Versionen angeboten."
"systembericht-woechentlich|konfiguration|system-wochenbericht.sh|Schreibt einen woechentlichen Systembericht|Sonntags 20:00 Uhr|Fasst einmal pro Woche den Gesamtzustand zusammen: Laufzeit, Auslastung, freier Speicher, Zustand der Pools, Anzahl laufender VMs und Container, letzte Sicherungen. Ein schneller Blick genuegt, um zu sehen, ob alles in Ordnung ist."
"gast-agent-pruefen-woechentlich|konfiguration|gast-agent-pruefen.sh|Findet VMs ohne Gast-Agent|Montags 09:30 Uhr|Ohne den QEMU-Gast-Agent kann Proxmox eine VM nicht sauber herunterfahren und keine konsistenten Sicherungen im laufenden Betrieb erstellen. Der Job listet alle VMs auf, bei denen der Agent fehlt oder nicht antwortet."
"ressourcen-trend-taeglich|konfiguration|ressourcen-auslastung-aufzeichnen.sh|Zeichnet die Auslastung fuer Trends auf|Taeglich 12:00 Uhr|Schreibt jeden Mittag eine Zeile mit Prozessor-, Arbeitsspeicher- und Speicherplatzauslastung in eine Datei. Nach ein paar Wochen sieht man daran gut, ob der Server langsam an seine Grenzen kommt - lange bevor es wirklich eng wird."
)

# ---------- Zugriff auf Job-Felder ----------

job_field() {
    echo "$1" | awk -F'|' -v f="$2" '{print $f}'
}

job_def_by_id() {
    local WANTED="$1" DEF
    for DEF in "${CRON_JOB_DEFS[@]}"; do
        [ "$(job_field "$DEF" 1)" == "$WANTED" ] && { echo "$DEF"; return 0; }
    done
    return 1
}

is_job_enabled() {
    [ -f "$CRON_FILE" ] && grep -q "# job:$1\$" "$CRON_FILE"
}

remove_job_line() {
    [ -f "$CRON_FILE" ] && sed -i "/# job:$1\$/d" "$CRON_FILE"
}

add_cron_line() {
    # $1 = Zeitplan+Befehl (ohne Marker), $2 = Job-ID
    touch "$CRON_FILE"
    remove_job_line "$2"
    echo "$1 # job:$2" >> "$CRON_FILE"
    chmod 644 "$CRON_FILE"
}

get_backup_storage() {
    local SAVED
    SAVED=$(conf_get "BACKUP_STORAGE")
    if [ -n "$SAVED" ]; then
        echo "$SAVED"
        return 0
    fi

    local ITEMS=() NAME TYPE
    while read -r NAME TYPE _; do
        [ -z "$NAME" ] && continue
        ITEMS+=("$NAME" "Typ: $TYPE")
    done < <(pvesm status 2>/dev/null | awk 'NR>1{print $1, $2}')

    if [ ${#ITEMS[@]} -eq 0 ]; then
        pause "Es konnte kein Speicher gefunden werden.\n\nBitte lege in der Proxmox-Weboberflaeche zuerst einen Speicher fuer Sicherungen an (Datacenter -> Storage)." "Kein Speicher gefunden"
        return 1
    fi

    local STORAGE
    STORAGE=$(menu_dialog "Speicher fuer Sicherungen" \
        "Wohin sollen die Sicherungen geschrieben werden?\n\nTipp: Am besten NICHT auf dieselbe Festplatte, auf der auch die VMs liegen - sonst sind bei einem Plattenausfall Original UND Sicherung weg." \
        22 78 10 "" "${ITEMS[@]}")
    [ -z "${STORAGE:-}" ] && return 1

    conf_set "BACKUP_STORAGE" "$STORAGE"
    echo "$STORAGE"
}
