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
race_results <- read.csv("f1_2024_data/race_results.csv")
qualifying   <- read.csv("f1_2024_data/qualifying_results.csv")
circuits     <- read.csv("f1_2024_data/circuits.csv")

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
df$finish_pos <- suppressWarnings(as.integer(df$Position.race))
df$finish_pos[df$Position.race %in% c("NC", "DQ")] <- DNF_POS
df$finish_pos[is.na(df$finish_pos)] <- DNF_POS

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

cat("\nUkljuceno vozaca:", length(profili),
    "| izostavljeno (zamjenski):",
    paste(setdiff(names(broj_utrka), glavni_vozaci), collapse = ", "), "\n")
cat("Profil Maxa Verstappena (stvarne pozicije 2024):\n")
print(profili[["Max Verstappen"]])

# --- 4. Bodovni sustav F1 -----------------------------------
n_vozaca <- length(profili)
bodovanje <- rep(0, n_vozaca)
bodovanje[1:10] <- c(25, 18, 15, 12, 10, 8, 6, 4, 2, 1)

# --- 5. Simulacija jedne sezone -----------------------------
simuliraj_sezonu <- function(profili, n_utrka = 24) {
  vozaci <- names(profili)
  ukupni_bodovi <- setNames(rep(0, length(vozaci)), vozaci)

  for (utrka in 1:n_utrka) {
    # Svaki vozac "izvuce" jedan stvarni rezultat iz svog profila.
    izvucene <- sapply(profili, function(p) sample(p, 1))
    # Rangiraj vozace; izjednacene pozicije razrijesi nasumicno.
    poredak <- order(izvucene, runif(length(izvucene)))
    bodovi_po_mjestu <- bodovanje[seq_along(poredak)]
    ukupni_bodovi[vozaci[poredak]] <-
      ukupni_bodovi[vozaci[poredak]] + bodovi_po_mjestu
  }
  ukupni_bodovi
}

# Test - jedna sezona
set.seed(42)
cat("\nPrimjer jedne simulirane sezone:\n")
print(sort(simuliraj_sezonu(profili), decreasing = TRUE))

# --- 6. Mnogo simulacija ------------------------------------
set.seed(42)
n_simulacija <- 50000   # povecaj za stabilnije procjene (npr. 1e6)

rezultati <- replicate(n_simulacija, simuliraj_sezonu(profili))
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
