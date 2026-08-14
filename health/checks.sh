#!/bin/bash
# ==========================================================
# CronJobs-Proxmox - Gesundheitspruefungen
# ==========================================================
# Sammelt den Zustand des Servers in vier Feldern je Punkt:
#
#   HEALTH_ID      Kurzname (fuer die Zuordnung der Loesung)
#   HEALTH_NAME    Anzeigename
#   HEALTH_STATE   GRUEN | GELB | ROT | GRAU
#   HEALTH_TEXT    Ergebnis in einem Satz
#   HEALTH_DETAIL  Ausfuehrliche Erklaerung fuer das Info-Fenster
#   HEALTH_FIX     Name der Funktion, die das Problem behebt (leer = keine)
#
# GRAU bedeutet: trifft auf diesen Server nicht zu (z.B. Cluster-
# Pruefung auf einem Einzelserver). Das ist kein Fehler.
# ==========================================================

HEALTH_ID=(); HEALTH_NAME=(); HEALTH_STATE=(); HEALTH_TEXT=(); HEALTH_DETAIL=(); HEALTH_FIX=()

health_add() {
    HEALTH_ID+=("$1"); HEALTH_NAME+=("$2"); HEALTH_STATE+=("$3")
    HEALTH_TEXT+=("$4"); HEALTH_DETAIL+=("$5"); HEALTH_FIX+=("$6")
}

# ---------- Einzelpruefungen ----------

pruefe_sicherung_vorhanden() {
    local GAESTE NEUESTE ALTER
    GAESTE=$(( $(qm list 2>/dev/null | tail -n +2 | wc -l) + $(pct list 2>/dev/null | tail -n +2 | wc -l) ))

    if [ "$GAESTE" -eq 0 ]; then
        health_add "sicherung" "Sicherung" "GRAU" \
            "Es gibt noch keine VMs oder Container" \
            "Auf diesem Server laeuft bisher weder eine virtuelle Maschine noch ein Container. Es gibt also auch nichts zu sichern.\n\nSobald du das erste System anlegst, solltest du hier eine Sicherung einrichten." ""
        return
    fi

    NEUESTE=$(find /var/lib/vz/dump /mnt/pve/*/dump -maxdepth 1 -name 'vzdump-*' -printf '%T@\n' 2>/dev/null | sort -n | tail -1)

    if [ -z "$NEUESTE" ]; then
        health_add "sicherung" "Sicherung" "ROT" \
            "Es wurde noch nie eine Sicherung erstellt" \
            "Auf diesem Server laufen $GAESTE System(e), aber es existiert keine einzige Sicherung.\n\nGeht die Festplatte kaputt oder loescht du versehentlich etwas, ist alles unwiederbringlich weg. Das ist mit Abstand das groesste Risiko auf diesem Server.\n\nEmpfehlung: unter 'Automatische Aufgaben' die Kategorie 'Sicherung' oeffnen und den Job backup-alle-vms-und-container.sh aktivieren." "fix_ampel_sicherung"
        return
    fi

    ALTER=$(( ( $(date +%s) - ${NEUESTE%.*} ) / 86400 ))
    if [ "$ALTER" -gt 7 ]; then
        health_add "sicherung" "Sicherung" "ROT" \
            "Letzte Sicherung ist $ALTER Tage alt" \
            "Die neueste Sicherung auf diesem Server ist $ALTER Tage alt.\n\nAlles, was seitdem passiert ist, waere bei einem Ausfall verloren. Moeglicherweise ist die automatische Sicherung fehlgeschlagen, ohne dass es jemand bemerkt hat - genau deshalb ist auch die E-Mail-Benachrichtigung so wichtig.\n\nPruefe die Protokolle und richte bei Bedarf eine taegliche Sicherung ein." "fix_ampel_sicherung"
    elif [ "$ALTER" -gt 2 ]; then
        health_add "sicherung" "Sicherung" "GELB" \
            "Letzte Sicherung vor $ALTER Tagen" \
            "Die neueste Sicherung ist $ALTER Tage alt. Das ist noch vertretbar, aber taeglich waere besser.\n\nUeberlege, ob du den Zeitplan enger setzen moechtest." "fix_ampel_sicherung"
    else
        health_add "sicherung" "Sicherung" "GRUEN" \
            "Aktuell (juengste Sicherung ist $ALTER Tag(e) alt)" \
            "Es existiert eine aktuelle Sicherung. Sehr gut.\n\nDenk daran, sie gelegentlich testweise zurueckzuspielen - eine nie getestete Sicherung ist keine Sicherung." ""
    fi
}

pruefe_sicherung_geplant() {
    local EIGEN=0 PVE=0
    [ -f "$CRON_FILE" ] && grep -q "# job:sicherung-" "$CRON_FILE" 2>/dev/null && EIGEN=1
    [ -s /etc/pve/jobs.cfg ] && grep -q "^vzdump:" /etc/pve/jobs.cfg 2>/dev/null && PVE=1

    if [ "$EIGEN" -eq 1 ] || [ "$PVE" -eq 1 ]; then
        local WOHER="ueber dieses Werkzeug"
        [ "$PVE" -eq 1 ] && [ "$EIGEN" -eq 0 ] && WOHER="ueber die Proxmox-Weboberflaeche"
        [ "$PVE" -eq 1 ] && [ "$EIGEN" -eq 1 ] && WOHER="ueber beide Wege"
        health_add "sicherungsplan" "Sicherungsplan" "GRUEN" \
            "Eine automatische Sicherung ist eingerichtet ($WOHER)" \
            "Es gibt einen Zeitplan, nach dem regelmaessig gesichert wird.\n\nEingerichtet $WOHER." ""
    else
        health_add "sicherungsplan" "Sicherungsplan" "ROT" \
            "Keine automatische Sicherung eingerichtet" \
            "Es ist kein Zeitplan hinterlegt, nach dem automatisch gesichert wird.\n\nVon Hand gesicherte Daten sind erfahrungsgemaess nach wenigen Wochen veraltet, weil man es schlicht vergisst. Eine automatische naechtliche Sicherung ist die wichtigste Einzelmassnahme ueberhaupt.\n\nUnter 'Automatische Aufgaben' -> 'Sicherung' einrichten." "fix_ampel_sicherung"
    fi
}

pruefe_speicherplatz() {
    local VOLL MOUNT FREI SCHLIMMSTE=0 SCHLIMM_MP="" SCHLIMM_FREI=""
    while read -r VOLL MOUNT FREI; do
        [ -z "$VOLL" ] && continue
        if [ "$VOLL" -gt "$SCHLIMMSTE" ]; then
            SCHLIMMSTE="$VOLL"; SCHLIMM_MP="$MOUNT"; SCHLIMM_FREI="$FREI"
        fi
    done < <(df -P -x tmpfs -x devtmpfs -x squashfs -x overlay 2>/dev/null | awk 'NR>1{gsub("%","",$5); print $5, $6, $4}')

    local FREI_LESBAR
    FREI_LESBAR=$(df -h "$SCHLIMM_MP" 2>/dev/null | awk 'NR==2{print $4}')

    if [ "$SCHLIMMSTE" -gt 90 ]; then
        health_add "speicherplatz" "Speicherplatz" "ROT" \
            "$SCHLIMM_MP ist zu ${SCHLIMMSTE}% voll (nur noch $FREI_LESBAR frei)" \
            "Das Laufwerk $SCHLIMM_MP ist zu ${SCHLIMMSTE} Prozent belegt, es sind nur noch $FREI_LESBAR frei.\n\nWenn die Systemplatte vollstaendig vollaeuft, geht bei Proxmox sehr schnell gar nichts mehr: die Weboberflaeche zeigt Fehler, VMs starten nicht mehr und die Konfiguration wird schreibgeschuetzt.\n\nDas laesst sich meist in einer Minute beheben - Protokolle begrenzen, Paketcache leeren, alte Sicherungen loeschen." "fix_speicher_freimachen"
    elif [ "$SCHLIMMSTE" -gt 80 ]; then
        health_add "speicherplatz" "Speicherplatz" "GELB" \
            "$SCHLIMM_MP ist zu ${SCHLIMMSTE}% voll ($FREI_LESBAR frei)" \
            "Das Laufwerk $SCHLIMM_MP ist zu ${SCHLIMMSTE} Prozent belegt.\n\nNoch ist alles in Ordnung, aber es lohnt sich, jetzt aufzuraeumen statt erst, wenn es eng wird." "fix_speicher_freimachen"
    else
        health_add "speicherplatz" "Speicherplatz" "GRUEN" \
            "Genug Platz (am vollsten: $SCHLIMM_MP mit ${SCHLIMMSTE}%)" \
            "Alle Laufwerke haben ausreichend freien Platz. Am staerksten belegt ist $SCHLIMM_MP mit ${SCHLIMMSTE} Prozent." ""
    fi
}

pruefe_festplatten() {
    if ! command -v smartctl >/dev/null 2>&1; then
        health_add "festplatten" "Festplatten" "GELB" \
            "Pruefprogramm smartmontools ist nicht installiert" \
            "Ohne das Programm smartctl kann der Zustand der Festplatten nicht ausgelesen werden.\n\nDamit faellt eine sterbende Platte erst auf, wenn sie bereits ausgefallen ist. Normalerweise kuendigt sich ein Defekt Wochen vorher an.\n\nNachinstallieren mit:  apt install smartmontools" ""
        return
    fi

    local PLATTE ERG DEFEKT ANZ=0 KAPUTT=0 WARNUNG=0 NAMEN=""
    for PLATTE in $(lsblk -d -n -o NAME 2>/dev/null | grep -E '^sd|^nvme'); do
        ANZ=$((ANZ+1))
        ERG=$(timeout 8 smartctl -H "/dev/$PLATTE" 2>/dev/null | grep -iE 'result|status' | head -1)
        if echo "$ERG" | grep -qiE 'failed|failing'; then
            KAPUTT=$((KAPUTT+1)); NAMEN="$NAMEN /dev/$PLATTE"
            continue
        fi
        DEFEKT=$(timeout 8 smartctl -A "/dev/$PLATTE" 2>/dev/null | awk '/Reallocated_Sector_Ct/{print $10; exit}')
        if [ -n "$DEFEKT" ] && [ "$DEFEKT" -gt 0 ] 2>/dev/null; then
            WARNUNG=$((WARNUNG+1)); NAMEN="$NAMEN /dev/$PLATTE($DEFEKT)"
        fi
    done

    if [ "$ANZ" -eq 0 ]; then
        health_add "festplatten" "Festplatten" "GRAU" "Keine pruefbaren Festplatten gefunden" \
            "Es wurden keine Festplatten gefunden, die eine Selbstdiagnose unterstuetzen. Bei virtuellen Umgebungen oder RAID-Controllern ist das normal." ""
    elif [ "$KAPUTT" -gt 0 ]; then
        health_add "festplatten" "Festplatten" "ROT" \
            "$KAPUTT von $ANZ Platten melden einen Defekt:$NAMEN" \
            "Eine oder mehrere Festplatten melden selbst, dass sie defekt sind:$NAMEN\n\nDas ist eine ernste Warnung. Die Platte kann in den naechsten Tagen oder Wochen komplett ausfallen.\n\nJetzt tun: eine aktuelle Sicherung erstellen und pruefen, dann die Platte tauschen." "fix_smart"
    elif [ "$WARNUNG" -gt 0 ]; then
        health_add "festplatten" "Festplatten" "GELB" \
            "$WARNUNG von $ANZ Platten haben defekte Sektoren:$NAMEN" \
            "Auf einer oder mehreren Platten wurden bereits defekte Sektoren ersetzt:$NAMEN\n\nDie Zahl in Klammern ist die Anzahl. Bleibt sie konstant, ist das meist unkritisch. Steigt sie ueber Wochen an, kuendigt sich ein Ausfall an.\n\nIm Auge behalten und fuer eine aktuelle Sicherung sorgen." "fix_smart"
    else
        health_add "festplatten" "Festplatten" "GRUEN" \
            "Alle $ANZ Platten melden sich gesund" \
            "Alle gefundenen Festplatten und SSDs melden ueber ihre Selbstdiagnose einen einwandfreien Zustand." ""
    fi
}

pruefe_zfs() {
    if ! command -v zpool >/dev/null 2>&1 || [ -z "$(zpool list -H -o name 2>/dev/null)" ]; then
        health_add "zfs" "ZFS-Speicher" "GRAU" "ZFS wird auf diesem Server nicht genutzt" \
            "Es wurde kein ZFS-Speicher gefunden. Dieser Punkt ist damit ohne Bedeutung." ""
        return
    fi

    local POOL ZUSTAND KAPUTT="" FEHLERHAFT="" ANZ=0
    for POOL in $(zpool list -H -o name 2>/dev/null); do
        ANZ=$((ANZ+1))
        ZUSTAND=$(zpool list -H -o health "$POOL" 2>/dev/null)
        [ "$ZUSTAND" != "ONLINE" ] && KAPUTT="$KAPUTT $POOL($ZUSTAND)"
        zpool status "$POOL" 2>/dev/null | grep -qE '[0-9]+ +[1-9][0-9]* +[0-9]+|errors: [1-9]' && FEHLERHAFT="$FEHLERHAFT $POOL"
    done

    if [ -n "$KAPUTT" ]; then
        health_add "zfs" "ZFS-Speicher" "ROT" "Pool nicht in Ordnung:$KAPUTT" \
            "Mindestens ein ZFS-Speicher ist nicht im Zustand ONLINE:$KAPUTT\n\nDEGRADED bedeutet: eine Festplatte ist ausgefallen. Der Speicher laeuft noch, aber ohne Ausfallsicherheit - faellt jetzt eine zweite Platte aus, sind die Daten weg.\n\nFAULTED bedeutet: schwerer Fehler, die Daten sind unmittelbar in Gefahr.\n\nIn beiden Faellen sofort handeln." "fix_zfs_status"
    elif [ -n "$FEHLERHAFT" ]; then
        health_add "zfs" "ZFS-Speicher" "GELB" "Fehlerzaehler steht nicht auf null:$FEHLERHAFT" \
            "Ein Pool meldet Lese-, Schreib- oder Pruefsummenfehler:$FEHLERHAFT\n\nHaeufig steckt ein lockeres Kabel oder eine ueberhitzte Platte dahinter. Wenn du die Ursache behoben hast, kannst du den Zaehler zuruecksetzen." "fix_zfs_status"
    else
        health_add "zfs" "ZFS-Speicher" "GRUEN" "$ANZ Pool(s) im Zustand ONLINE" \
            "Alle ZFS-Speicher sind fehlerfrei.\n\nDenk daran, monatlich eine Datenpruefung (Scrub) laufen zu lassen - das findet stille Fehler, bevor sie zum Problem werden." ""
    fi
}

pruefe_speicher_erreichbar() {
    local INAKTIV="" ANZ=0 NAME STATUS
    while read -r NAME STATUS; do
        [ -z "$NAME" ] && continue
        ANZ=$((ANZ+1))
        [ "$STATUS" != "active" ] && INAKTIV="$INAKTIV $NAME"
    done < <(pvesm status 2>/dev/null | awk 'NR>1{print $1, $3}')

    if [ "$ANZ" -eq 0 ]; then
        health_add "speicher" "Speicher erreichbar" "GRAU" "Keine Angaben verfuegbar" \
            "Der Zustand der Speicher konnte nicht abgefragt werden." ""
    elif [ -n "$INAKTIV" ]; then
        health_add "speicher" "Speicher erreichbar" "ROT" "Nicht erreichbar:$INAKTIV" \
            "Mindestens ein eingebundener Speicher antwortet nicht:$INAKTIV\n\nVMs, die darauf liegen, starten nicht mehr, und Sicherungen dorthin schlagen fehl.\n\nHaeufige Ursachen: das NAS ist ausgeschaltet, das Netzwerkkabel steckt nicht, die Zugangsdaten wurden geaendert." "fix_speicher_erreichbarkeit"
    else
        health_add "speicher" "Speicher erreichbar" "GRUEN" "Alle $ANZ Speicher antworten" \
            "Alle in Proxmox eingebundenen Speicher sind erreichbar." ""
    fi
}

pruefe_updates() {
    local LISTE ANZ=0 SICHER=0
    LISTE=$(timeout 20 apt-get -s dist-upgrade 2>/dev/null | grep -c '^Inst ')
    ANZ=${LISTE:-0}
    SICHER=$(timeout 20 apt-get -s dist-upgrade 2>/dev/null | grep -ci '^Inst.*security')

    if [ "${SICHER:-0}" -gt 0 ]; then
        health_add "updates" "Updates" "ROT" "$ANZ Updates verfuegbar, davon $SICHER sicherheitsrelevant" \
            "Es stehen $ANZ Aktualisierungen bereit, davon $SICHER mit Sicherheitsbezug.\n\nSicherheitsupdates schliessen bekannte Luecken und sollten zeitnah eingespielt werden - besonders, wenn der Server aus dem Internet erreichbar ist.\n\nDer Vorgang dauert meist wenige Minuten, laufende VMs sind davon nicht betroffen." "fix_updates_installieren"
    elif [ "$ANZ" -gt 0 ]; then
        health_add "updates" "Updates" "GELB" "$ANZ Updates verfuegbar" \
            "Es stehen $ANZ Aktualisierungen bereit, keine davon sicherheitskritisch.\n\nDu kannst sie in Ruhe zu einem passenden Zeitpunkt einspielen. Bei einem Kernel-Update ist danach ein Neustart faellig." "fix_updates_installieren"
    else
        health_add "updates" "Updates" "GRUEN" "System ist auf dem neuesten Stand" \
            "Es sind keine Aktualisierungen ausstehend." ""
    fi
}

pruefe_paketquellen() {
    local ENT=0 NOSUB=0
    grep -rqE '^[^#]*enterprise\.proxmox\.com' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null && ENT=1
    grep -rq 'enterprise\.proxmox\.com' /etc/apt/sources.list.d/*.sources 2>/dev/null && \
        ! grep -rqi 'Enabled: *false' /etc/apt/sources.list.d/*.sources 2>/dev/null && ENT=1
    grep -rqE '^[^#]*pve-no-subscription' /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null && NOSUB=1

    local HAT_ABO=0
    pvesubscription get 2>/dev/null | grep -qi 'status: *active' && HAT_ABO=1

    if [ "$ENT" -eq 1 ] && [ "$HAT_ABO" -eq 0 ]; then
        health_add "paketquellen" "Paketquellen" "ROT" "Enterprise-Repo aktiv, aber keine Subscription" \
            "Es ist die kostenpflichtige Paketquelle (Enterprise) eingetragen, aber keine gueltige Subscription vorhanden.\n\nDadurch schlaegt jede Aktualisierung mit einem Anmeldefehler fehl, und bei jeder Anmeldung erscheint das Hinweisfenster 'No valid subscription'.\n\nDie Loesung: Enterprise-Quelle abschalten, kostenlose No-Subscription-Quelle eintragen. Das ist der uebliche Weg fuer private Server." "fix_subscription_hinweis"
    elif [ "$NOSUB" -eq 0 ] && [ "$HAT_ABO" -eq 0 ]; then
        health_add "paketquellen" "Paketquellen" "GELB" "Keine nutzbare Proxmox-Paketquelle eingetragen" \
            "Es ist weder eine Subscription vorhanden noch die kostenlose Paketquelle eingetragen.\n\nDamit bekommt dieser Server keine Proxmox-Aktualisierungen mehr." "fix_subscription_hinweis"
    else
        health_add "paketquellen" "Paketquellen" "GRUEN" "Passend eingerichtet" \
            "Die Paketquellen sind so eingerichtet, dass Aktualisierungen funktionieren." ""
    fi
}

pruefe_benachrichtigung() {
    local MAIL=""
    MAIL=$(pveum user list 2>/dev/null | awk -F'│|\\|' '/root@pam/{print $3}' | tr -d ' ')
    [ -z "$MAIL" ] && MAIL=$(grep -A5 '^user:root@pam' /etc/pve/user.cfg 2>/dev/null | grep -oP '[\w.+-]+@[\w.-]+' | head -1)
    [ -z "$MAIL" ] && MAIL=$(grep -oP '^user:root@pam:[^:]*:[^:]*:[^:]*:[^:]*:\K[\w.+-]+@[\w.-]+' /etc/pve/user.cfg 2>/dev/null | head -1)

    local ZIELE=0
    [ -f /etc/pve/notifications.cfg ] && ZIELE=$(grep -cE '^(smtp|gotify|webhook|sendmail):' /etc/pve/notifications.cfg 2>/dev/null)

    if [ -z "$MAIL" ] && [ "${ZIELE:-0}" -eq 0 ]; then
        health_add "benachrichtigung" "Benachrichtigung" "ROT" "Keine E-Mail-Adresse hinterlegt" \
            "Es ist weder eine E-Mail-Adresse fuer den Benutzer root hinterlegt noch ein anderes Benachrichtigungsziel eingerichtet.\n\nDas ist heimtueckischer, als es klingt: Wenn die naechtliche Sicherung fehlschlaegt oder eine Festplatte stirbt, erfaehrt es niemand. Der Server meldet es brav - aber an niemanden.\n\nEinrichten in der Weboberflaeche unter\n  Datacenter -> Notifications\nund die Adresse beim Benutzer root unter\n  Datacenter -> Permissions -> Users" ""
    elif [ -z "$MAIL" ]; then
        health_add "benachrichtigung" "Benachrichtigung" "GELB" "Benachrichtigungsziel vorhanden, aber keine Adresse bei root" \
            "Es ist zwar ein Benachrichtigungsziel eingerichtet, dem Benutzer root fehlt aber eine E-Mail-Adresse. Manche Meldungen gehen dadurch verloren." ""
    else
        health_add "benachrichtigung" "Benachrichtigung" "GRUEN" "E-Mail hinterlegt: $MAIL" \
            "Meldungen gehen an $MAIL.\n\nTipp: Pruefe gelegentlich, ob dort auch wirklich etwas ankommt und nicht alles im Spam-Ordner landet." ""
    fi
}

pruefe_zeit() {
    local SYNC
    SYNC=$(timedatectl show -p NTPSynchronized --value 2>/dev/null)
    if [ "$SYNC" == "yes" ]; then
        health_add "zeit" "Uhrzeit" "GRUEN" "Uhr laeuft synchron" \
            "Die Systemuhr wird automatisch abgeglichen und geht richtig." ""
    elif [ -z "$SYNC" ]; then
        health_add "zeit" "Uhrzeit" "GRAU" "Nicht pruefbar" \
            "Der Zustand der Zeitsynchronisierung konnte nicht ermittelt werden." ""
    else
        health_add "zeit" "Uhrzeit" "GELB" "Uhr wird nicht automatisch abgeglichen" \
            "Die Systemuhr laeuft ohne automatischen Abgleich.\n\nEine falsch gehende Uhr verursacht erstaunlich viele Folgeprobleme: Zertifikate gelten als ungueltig, im Cluster streiten sich die Server, Sicherungen bekommen falsche Zeitstempel und Protokolle lassen sich nicht mehr sinnvoll lesen." "fix_zeit"
    fi
}

pruefe_kernel() {
    local LAEUFT NEUSTE
    LAEUFT=$(uname -r)
    NEUSTE=$(dpkg -l 2>/dev/null | grep -E 'proxmox-kernel-[0-9]|pve-kernel-[0-9]' | awk '{print $3}' | sed 's/^[0-9]*://' | sort -V | tail -1)
    if [ -n "$NEUSTE" ] && ! echo "$NEUSTE" | grep -q "$(echo "$LAEUFT" | cut -d- -f1)"; then
        health_add "kernel" "Neustart" "GELB" "Ein Neustart ist faellig (neuer Kernel installiert)" \
            "Es laeuft noch der Kernel $LAEUFT, installiert ist bereits $NEUSTE.\n\nErst nach einem Neustart ist die neue Version wirklich aktiv - das betrifft auch Sicherheitskorrekturen im Kernel.\n\nPlane den Neustart ausserhalb der Nutzungszeit ein, die VMs fahren dabei mit herunter." ""
    else
        health_add "kernel" "Neustart" "GRUEN" "Kein Neustart noetig" \
            "Der laufende Kernel ist der aktuell installierte. Es steht kein Neustart an." ""
    fi
}

pruefe_firewall() {
    if ! command -v pve-firewall >/dev/null 2>&1; then
        health_add "firewall" "Firewall" "GRAU" "Nicht verfuegbar" "Die Proxmox-Firewall steht auf diesem System nicht zur Verfuegung." ""
        return
    fi
    if pve-firewall status 2>/dev/null | head -1 | grep -qi "running"; then
        health_add "firewall" "Firewall" "GRUEN" "Firewall ist aktiv" \
            "Die Proxmox-Firewall laeuft.\n\nPruefe gelegentlich, ob die Regeln noch zu deinem Netz passen." ""
    else
        health_add "firewall" "Firewall" "GELB" "Firewall ist ausgeschaltet" \
            "Die Proxmox-Firewall ist nicht aktiv.\n\nIn einem abgeschotteten Heimnetz hinter einem Router ist das vertretbar. Ist der Server dagegen aus dem Internet erreichbar, solltest du sie unbedingt einschalten.\n\nVorsicht: Vor dem Einschalten die Regeln pruefen, sonst sperrst du dich unter Umstaenden selbst aus." "fix_firewall"
    fi
}

pruefe_cluster() {
    if [ ! -f /etc/pve/corosync.conf ]; then
        health_add "cluster" "Cluster" "GRAU" "Einzelserver, kein Cluster" \
            "Dieser Server ist nicht Teil eines Clusters. Alle Cluster-Pruefungen entfallen damit." ""
        return
    fi
    if pvecm status 2>/dev/null | grep -qi "Quorate: *Yes"; then
        health_add "cluster" "Cluster" "GRUEN" "Cluster ist beschlussfaehig" \
            "Es sind genug Server im Cluster erreichbar. Aenderungen koennen gespeichert werden." ""
    else
        health_add "cluster" "Cluster" "ROT" "Cluster hat kein Quorum" \
            "Es sind zu wenige Server im Cluster erreichbar.\n\nDie Folge: Die Konfiguration ist jetzt schreibgeschuetzt, VMs lassen sich nicht mehr starten, und bei aktiver Hochverfuegbarkeit koennen sich Server sogar selbst neu starten.\n\nPruefe zuerst, ob die anderen Server laufen und das Netzwerk zwischen ihnen in Ordnung ist." "fix_cluster_status"
    fi
}

pruefe_zfs_arc() {
    [ -f /proc/spl/kstat/zfs/arcstats ] || return
    local ARC_GB RAM_GB ANTEIL
    ARC_GB=$(awk '/^size /{printf "%.1f", $3/1073741824}' /proc/spl/kstat/zfs/arcstats)
    RAM_GB=$(free -g | awk '/^Mem:/{print $2}')
    [ -z "$RAM_GB" ] || [ "$RAM_GB" -eq 0 ] && return
    ANTEIL=$(awk -v a="$ARC_GB" -v r="$RAM_GB" 'BEGIN{printf "%.0f", a*100/r}')

    if [ "$ANTEIL" -gt 55 ]; then
        health_add "zfsarc" "ZFS-Arbeitsspeicher" "GELB" \
            "ZFS belegt ${ARC_GB} GB von ${RAM_GB} GB (${ANTEIL}%)" \
            "ZFS nutzt ${ARC_GB} GB des Arbeitsspeichers als Zwischenspeicher, das sind ${ANTEIL} Prozent der insgesamt ${RAM_GB} GB.\n\nZFS gibt diesen Speicher zwar wieder frei, wenn eine VM ihn braucht. In der Praxis ist eine feste Obergrenze aber uebersichtlicher, weil sonst schwer einzuschaetzen ist, wie viel Platz fuer neue VMs bleibt.\n\nFaustregel: hoechstens ein Viertel bis die Haelfte des Arbeitsspeichers." "fix_zfs_arc_begrenzen"
    else
        health_add "zfsarc" "ZFS-Arbeitsspeicher" "GRUEN" \
            "ZFS belegt ${ARC_GB} GB von ${RAM_GB} GB (${ANTEIL}%)" \
            "Der Zwischenspeicher von ZFS bewegt sich in einem unauffaelligen Rahmen." ""
    fi
}

# ---------- Alle Pruefungen ausfuehren ----------

health_run() {
    HEALTH_ID=(); HEALTH_NAME=(); HEALTH_STATE=(); HEALTH_TEXT=(); HEALTH_DETAIL=(); HEALTH_FIX=()
    pruefe_sicherung_vorhanden
    pruefe_sicherung_geplant
    pruefe_speicherplatz
    pruefe_speicher_erreichbar
    pruefe_festplatten
    pruefe_zfs
    pruefe_zfs_arc
    pruefe_updates
    pruefe_paketquellen
    pruefe_benachrichtigung
    pruefe_zeit
    pruefe_kernel
    pruefe_firewall
    pruefe_cluster
}

health_zaehle() {
    # $1 = Zustand -> Anzahl
    local I ANZ=0
    for I in "${!HEALTH_STATE[@]}"; do
        [ "${HEALTH_STATE[$I]}" == "$1" ] && ANZ=$((ANZ+1))
    done
    echo "$ANZ"
}
