# ============================================================
#  Projekt MOD_SIM - Predikcija prvaka F1 (Monte Carlo)
#  Autor: Vito Radola
#
#  Ideja: iz stvarnih rezultata sezone 2024 napravimo "profil"
#  svakog vozaca (skup pozicija koje je stvarno osvajao), pa
#  simuliramo cijelu sljedecu sezonu mnogo puta i gledamo koliko
#  cesto tko osvoji naslov -> vjerojatnost prvaka.
#
#  Podaci: cisti CSV-ovi iz mape f1_2024_data/ (sezona 2024).
#  (Stari, losi CSV-ovi vise se ne koriste.)
# ============================================================

# --- 1. Ucitavanje podataka ---------------------------------
race_results  <- read.csv("f1_2024_data/race_results.csv")
qualifying    <- read.csv("f1_2024_data/qualifying_results.csv")
circuits      <- read.csv("f1_2024_data/circuits.csv")
sprint        <- read.csv("f1_2024_data/sprint_results.csv")
sprint_quali  <- read.csv("f1_2024_data/sprint_qualifying_results.csv")

# Spoj rezultata utrke i kvalifikacija (kljuc: krug + vozac).
# suffixes razdvaja istoimene stupce (Position -> Position.race / .quali).
df <- merge(
  race_results, qualifying,
  by = c("Round", "Driver"),
  suffixes = c(".race", ".quali"),
  all.x = TRUE
)

# Dodaj duljinu staze i broj krugova iz circuits (po Round-u).
df <- merge(
  df,
  circuits[, c("Round", "Circuit.Length.km.", "Number.of.Laps")],
  by = "Round", all.x = TRUE
)

# --- 2. Ciscenje i izvedeni stupci --------------------------
# Pretvori vrijeme "1:29.179" ili "+0.321" u sekunde.
time_to_sec <- function(x) {
  if (is.na(x) || x == "") return(NA_real_)
  if (grepl("^\\+", x)) return(suppressWarnings(as.numeric(sub("\\+", "", x))))
  parts <- strsplit(x, ":")[[1]]
  if (length(parts) == 2) {
    return(suppressWarnings(as.numeric(parts[1]) * 60 + as.numeric(parts[2])))
  }
  suppressWarnings(as.numeric(x))
}

df$q1_sec <- sapply(df$Q1, time_to_sec)
df$q2_sec <- sapply(df$Q2, time_to_sec)
df$q3_sec <- sapply(df$Q3, time_to_sec)

# Pole pozicija = kvalifikacijska pozicija 1; najbrzi krug iz "Set Fastest Lap".
df$pole_position <- as.factor(ifelse(df$Position.quali == 1, "Yes", "No"))
df$fastest_lap   <- as.factor(df$Set.Fastest.Lap)

# Zavrsnu poziciju pretvori u broj. NC (nije klasificiran) i DQ
# (diskvalifikacija) tretiramo kao "kraj polja" -> bez bodova,
# ali i dalje rangiraju zadnji u simulaciji.
DNF_POS <- 20L
poz_u_broj <- function(poz) {
  v <- suppressWarnings(as.integer(poz))
  v[poz %in% c("NC", "DQ")] <- DNF_POS   # nije klasificiran / diskvalificiran
  v[is.na(v)] <- DNF_POS
  v
}
df$finish_pos <- poz_u_broj(df$Position.race)

# Sprint utrke (2024: 6 sprinteva) - ista logika, zasebni profil.
sprint$finish_pos <- poz_u_broj(sprint$Position)
n_sprint <- length(unique(sprint$Round))

# Kvalifikacijske (startne) pozicije - za utrke i za sprinteve.
qualifying$grid_pos   <- poz_u_broj(qualifying$Position)
sprint_quali$grid_pos <- poz_u_broj(sprint_quali$Position)

str(df[, c("Round", "Driver", "Team.race", "finish_pos",
           "Position.quali", "q3_sec", "pole_position", "fastest_lap")])

# --- 3. Profili vozaca --------------------------------------
# Izbaci vozace koji su odvozili premalo utrka (zamjenski vozaci),
# da ne iskrive borbu za naslov. min_utrka <- 1 vraca staro
# ponasanje (svi vozaci ukljuceni).
min_utrka <- 10
broj_utrka <- table(df$Driver)
glavni_vozaci <- names(broj_utrka[broj_utrka >= min_utrka])

df_glavni <- df[df$Driver %in% glavni_vozaci, ]
profili <- split(df_glavni$finish_pos, df_glavni$Driver)

# Sprint profili (samo glavni vozaci). Ako vozac nije vozio nijedan
# sprint, dodijeli mu profil = zadnje mjesto (bez sprint bodova).
sprint_glavni <- sprint[sprint$Driver %in% glavni_vozaci, ]
sprint_profili <- split(sprint_glavni$finish_pos, sprint_glavni$Driver)
for (v in glavni_vozaci) {
  if (is.null(sprint_profili[[v]])) sprint_profili[[v]] <- DNF_POS
}
sprint_profili <- sprint_profili[names(profili)]   # isti redoslijed

# Profili startnih pozicija (kvalifikacije). Sluze za "tezinu" -
# laksa je pobjeda s pole positiona nego s zacelja.
napravi_profil <- function(podaci, stupac_pozicije) {
  pod <- podaci[podaci$Driver %in% glavni_vozaci, ]
  pr <- split(pod[[stupac_pozicije]], pod$Driver)
  for (v in glavni_vozaci) if (is.null(pr[[v]])) pr[[v]] <- DNF_POS
  pr[names(profili)]
}
quali_profili        <- napravi_profil(qualifying, "grid_pos")
sprint_quali_profili <- napravi_profil(sprint_quali, "grid_pos")

cat("\nUkljuceno vozaca:", length(profili),
    "| izostavljeno (zamjenski):",
    paste(setdiff(names(broj_utrka), glavni_vozaci), collapse = ", "), "\n")
cat("Profil Maxa Verstappena (stvarne pozicije 2024):\n")
print(profili[["Max Verstappen"]])

# --- 4. Bodovni sustav F1 -----------------------------------
n_vozaca <- length(profili)
bodovanje <- rep(0, n_vozaca)
bodovanje[1:10] <- c(25, 18, 15, 12, 10, 8, 6, 4, 2, 1)

# Sprint bodovi: prvih 8 mjesta (8-7-6-5-4-3-2-1).
bodovanje_sprint <- rep(0, n_vozaca)
bodovanje_sprint[1:8] <- c(8, 7, 6, 5, 4, 3, 2, 1)

# Koliko startna (kvalifikacijska) pozicija utjece na ishod natjecanja.
# 0   = ishod ovisi samo o profilu zavrsnih pozicija (staro ponasanje)
# 1   = ishod ovisi samo o startnoj poziciji
# 0.35 = mjesavina (start se uzima u obzir, ali ne dominira).
tezina_kvalifikacija <- 0.35

# --- 5. Simulacija jedne sezone -----------------------------
# Jedno "natjecanje": svaki vozac izvuce zavrsnu poziciju iz svog profila
# I startnu poziciju iz kvalifikacijskog profila. Konacni "rezultat" je
# tezinska mjesavina to dvoje (w = tezina starta) - tako bolji start
# povlaci vozaca prema naprijed. Zatim se rangira i dijele bodovi.
odradi_natjecanje <- function(finish_profili, quali_profili, bodovi, vozaci, ukupni, w) {
  izvuceni_finish <- sapply(finish_profili, function(p) sample(p, 1))
  izvuceni_start  <- sapply(quali_profili,  function(p) sample(p, 1))
  skor <- (1 - w) * izvuceni_finish + w * izvuceni_start
  poredak <- order(skor, runif(length(skor)))  # ties = nasumicno
  ukupni[vozaci[poredak]] <- ukupni[vozaci[poredak]] + bodovi[seq_along(poredak)]
  ukupni
}

simuliraj_sezonu <- function(profili, quali_profili,
                             sprint_profili, sprint_quali_profili,
                             w = 0.35, n_utrka = 24, n_sprint = 6) {
  vozaci <- names(profili)
  ukupni_bodovi <- setNames(rep(0, length(vozaci)), vozaci)

  # Glavne utrke (zavrsni profil + kvalifikacije)
  for (utrka in 1:n_utrka) {
    ukupni_bodovi <- odradi_natjecanje(profili, quali_profili,
                                       bodovanje, vozaci, ukupni_bodovi, w)
  }
  # Sprint utrke (sprint profil + sprint kvalifikacije)
  for (s in seq_len(n_sprint)) {
    ukupni_bodovi <- odradi_natjecanje(sprint_profili, sprint_quali_profili,
                                       bodovanje_sprint, vozaci, ukupni_bodovi, w)
  }
  ukupni_bodovi
}

# Test - jedna sezona
set.seed(42)
cat("\nPrimjer jedne simulirane sezone (utrke + sprintevi, s tezinom starta):\n")
print(sort(simuliraj_sezonu(profili, quali_profili, sprint_profili, sprint_quali_profili,
                            w = tezina_kvalifikacija, n_sprint = n_sprint), decreasing = TRUE))

# --- 6. Mnogo simulacija ------------------------------------
set.seed(42)
n_simulacija <- 50000   # povecaj za stabilnije procjene (npr. 1e6)

rezultati <- replicate(n_simulacija, simuliraj_sezonu(
  profili, quali_profili, sprint_profili, sprint_quali_profili,
  w = tezina_kvalifikacija, n_sprint = n_sprint))
# rezultati: matrica [vozac x simulacija]

# Pobjednik svake sezone = vozac s najvise bodova.
pobjednici <- rownames(rezultati)[apply(rezultati, 2, which.max)]

vjerojatnosti <- sort(table(pobjednici) / n_simulacija * 100, decreasing = TRUE)
prosjek_bodova <- sort(rowMeans(rezultati), decreasing = TRUE)

cat("\n=== Vjerojatnost osvajanja naslova (%) ===\n")
print(round(vjerojatnosti, 2))

cat("\n=== Prosjecan broj bodova po sezoni ===\n")
print(round(prosjek_bodova, 1))

cat("\nPredvideni prvak sljedece sezone:", names(vjerojatnosti)[1],
    sprintf("(%.1f%% vjerojatnosti)\n", as.numeric(vjerojatnosti)[1]))
