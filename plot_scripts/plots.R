library(tidyverse)
library(cowplot)

pdf(NULL)
dir.create("plots")

data <- read_csv("data/rivm_corona_in_nl.csv")

# daily data
data_daily <- read_csv("data/rivm_corona_in_nl_daily.csv")
fata <- read_csv("data/rivm_corona_in_nl_fatalities.csv")
hosp <- read_csv("data/rivm_corona_in_nl_hosp.csv")

measures <- read_csv("ext/maatregelen.csv") %>%
  mutate(name = forcats::fct_reorder(maatregel, start_datum))

# combine daily data
daily <- data_daily %>%
  mutate(meas = "Positief geteste patiënten") %>%
  bind_rows(hosp %>%
              mutate(meas = "Gehospitaliseerde patiënten")) %>%
  bind_rows(fata %>%
              mutate(meas = "Overleden patiënten"))

# combine daily increase
daily_diff <- data_daily %>%
  mutate(
    Aantal = Aantal - lag(Aantal),
    meas = "Positief geteste patiënten"
  ) %>%
  bind_rows(hosp %>%
              mutate(
                Aantal = Aantal - lag(Aantal),
                meas = "Gehospitaliseerde patiënten")) %>%
  bind_rows(fata %>%
              mutate(
                Aantal = Aantal - lag(Aantal),
                meas = "Overleden patiënten"))


g1 = daily %>%
  ggplot(aes(x = Datum, y = Aantal, colour = meas)) +
  geom_line() + 
  theme_minimal() + 
  theme(axis.title.x=element_blank(),
        axis.title.y=element_blank(),
        legend.pos = "bottom",
        legend.title = element_blank()) +
  scale_color_manual(values=c("#999999", "#E69F00", "#56B4E9")) + 
  ggtitle("Totaal besmettingen")

g2 = daily_diff %>%
  ggplot(aes(x = Datum, y = Aantal, colour = meas)) +
  geom_line() + 
  theme_minimal() + 
  theme(axis.title.x=element_blank(),
        axis.title.y=element_blank(),
        legend.pos = "bottom",
        legend.title = element_blank()) +
  scale_color_manual(values=c("#999999", "#E69F00", "#56B4E9")) + 
  ggtitle("Toename besmettingen")

plot_grid(g1, g2) +
  ggsave("plots/overview_plot.png", width = 10, height=4)


(daily %>%
  ggplot(aes(x = Datum, y = Aantal, colour = meas)) +
  geom_line() +
  scale_x_date(
    date_labels = "%d-%m-%Y",
    date_breaks = "1 weeks",
    date_minor_breaks = "1 days") +
  geom_rect(aes(xmin = start_datum,
                xmax = verwachtte_einddatum,
                ymin = -Inf,
                ymax = -0.025 * max(data_daily$Aantal, na.rm = TRUE),
                fill = name),
            inherit.aes = FALSE, data = measures) +
  geom_rug(aes(x = start_datum), inherit.aes = FALSE, data = measures) +
  coord_cartesian(xlim = c(min(data_daily$Datum), max(data_daily$Datum))) +
  scale_fill_viridis_d("Maatregel", guide = guide_legend(direction = "vertical")) +
  scale_colour_discrete("", guide = guide_legend(direction = "vertical")) +
  ggtitle("Aantal positief-geteste Coronavirus besmettingen in Nederland") +
  theme_minimal() +
  theme(axis.title.x=element_blank(),
        axis.title.y=element_blank(),
        legend.pos = "bottom",
        legend.key.size = unit(1, "mm"),
        legend.text = element_text(size = 6)) +
  ggsave("plots/timeline.png", width = 6, height=4))

### Top 10 municipalities

# top 10 municipalities on the most recent day
top_10_municipalities <- data %>%
  filter(!is.na(Gemeentenaam)) %>%
  arrange(desc(Datum), desc(Aantal)) %>%
  filter(Gemeentenaam %in% head(Gemeentenaam, 10))

# make plot
top_10_municipalities %>%
  ggplot(aes(Datum, Aantal, color=Gemeentenaam)) +
  geom_line() +
  theme_minimal() +
  scale_x_date(date_breaks = "1 weeks",
               date_minor_breaks = "1 days") +
  theme(axis.title.x=element_blank(),
        axis.title.y=element_blank()) +
  ggtitle("Gemeentes met de meeste positief-geteste Coronavirus besmettingen") +
  ggsave("plots/top_municipalities.png", width = 6, height=4)

### Per province
data %>%
  filter(Datum == max(Datum), !is.na(Gemeentenaam)) %>%
  mutate(Provincie = forcats::fct_reorder(
    Provincienaam, Aantal, .fun = sum, .desc = TRUE)) %>%
  ggplot(aes(Provincie, Aantal)) +
  geom_col() +
  theme_minimal() +
  theme(axis.text.x=element_text(angle=45,hjust=1,vjust=1.1)) +
  theme(axis.title.x=element_blank(),
        axis.title.y=element_blank()) +
  labs(title = "Positief-geteste Coronavirus besmettingen per provincie") +
  ggsave("plots/province_count.png", width = 6, height=4)

data %>%
  filter(!is.na(Gemeentenaam)) %>%
  group_by(Provincienaam, Datum) %>%
  summarise(Aantal = sum(Aantal, na.rm = T)) %>%
  ggplot(aes(Datum, Aantal, color=Provincienaam)) +
  geom_line() +
  theme_minimal() +
  scale_x_date(date_labels = "%d-%m-%Y",
               date_breaks = "1 weeks",
               date_minor_breaks = "1 days") +
  labs(title = "Positief-geteste Coronavirus besmettingen per provincie") +
  theme(axis.title.x=element_blank(),
        axis.title.y=element_blank()) +
  ggsave("plots/province_count_time.png", width = 6, height=4)


### Model fits

## plots
data_daily_ext <- data_daily %>%
  # add some new rows for which we wish to predict the values
  bind_rows(tibble(Datum = seq(max(.$Datum) + 1, max(.$Datum) + 3, 1))) %>%
  arrange(Datum)

exponential.model <- lm(log(Aantal + 1) ~ Datum, data = filter(data_daily_ext, Aantal > 200))
summary(exponential.model)

pred <- cbind(data_daily_ext,
              exp(predict(exponential.model,
                          newdata = list(Datum = data_daily_ext$Datum),
                          interval = "confidence"))) %>%
  mutate(new = Aantal - lag(Aantal),
         growth = new / lag(new),
         # Vincent rescaled to -1 and 1 first
         ds = scales::rescale(Datum, to = c(-1, 1)),
         as = scales::rescale(Aantal, to = c(-1, 1)))

# NOTE: this plot is currently not used, as it is the same as what is done in Python currently
# try to find the inflection point of the sigmoidal fit
pred %>%
  mutate(new = Aantal - lag(Aantal),
         growth = new / lag(new)) %>%
  ggplot(aes(x = Datum, y = growth)) +
  geom_point() +
  geom_smooth(method = "lm") +
  geom_hline(yintercept = 1) +
  ggtitle("Groeisnelheid van positief-geteste Corona besmettingen in Nederland") +
  theme_minimal() +
  scale_x_date(date_labels = "%d-%m-%Y",
               date_breaks = "1 weeks",
               date_minor_breaks = "1 days") +
  theme(axis.title.x=element_blank(),
        axis.title.y=element_blank()) +
  ggsave("plots/growth_rate_time.png", width = 6, height=4)

pred %>%
  ggplot(aes(Datum, Aantal)) +
  geom_ribbon(aes(ymin = lwr, ymax = upr), alpha = .2, fill = "red") +
  geom_line(aes(y = fit), colour = "red") +
  # only points for future dates?
  geom_point(aes(y = fit), colour = "red") +
  geom_line() +
  geom_point() +
  ylim(0, NA) +
  scale_x_date(date_labels = "%d-%m-%Y",
               date_breaks = "1 weeks",
               date_minor_breaks = "1 days") +
  theme_minimal() +
  theme(axis.title.x=element_blank(),
        axis.title.y=element_blank()) +
  labs(title = "Aantal positief-geteste Coronavirus besmettingen",
       subtitle = "met exponentiële groei model voor >200 besmettingen") +
  ggsave("plots/prediction.png", width = 6, height=4)

pred %>%
  ggplot(aes(Datum, Aantal)) +
  geom_ribbon(aes(ymin = lwr, ymax = upr), alpha = .2, fill = "red") +
  geom_line(aes(y = fit), colour = "red") +
  # only points for future dates?
  geom_point(aes(y = fit), colour = "red",
             data = filter(pred, Datum > max(data_daily$Datum))) +
  geom_line() +
  geom_point() +
  scale_y_log10() +
  scale_x_date(date_labels = "%d-%m-%Y",
               date_breaks = "1 weeks",
               date_minor_breaks = "1 days") +
  theme_minimal() +
  theme(axis.title.x=element_blank(),
        axis.title.y=element_blank()) +
  labs(title = "Aantal positief-geteste Coronavirus besmettingen",
       subtitle = "met exponentiële groei model voor >200 op een logaritmische schaal") +
  ggsave("plots/prediction_log10.png", width = 6, height=4)

# maps
library(sf)

# download province shapefile data
province_shp <- st_read("ext/NLD_adm/NLD_adm1.shp") %>%
  filter(ENGTYPE_1=="Province") %>%
  select(NAME_1)

mun <- read_csv2(
  "ext/Gemeenten_alfabetisch_2019.csv",
  col_types = cols(Gemeentecode = "i")
)

# plot map
province_data <- data %>%
  filter(!is.na(Gemeentenaam)) %>%
  group_by(Datum, Provincienaam) %>%
  summarise(Aantal = sum(Aantal, na.rm = T)) %>%
  ungroup() %>%
  left_join(province_shp, by=c("Provincienaam"="NAME_1"))


province_data %>%
  filter(Datum > max(Datum) - 3) %>%
  ggplot() +
  geom_sf(aes(fill=Aantal, color=Aantal, geometry = geometry)) +
  facet_grid(cols = vars(Datum)) +
  theme_minimal() +
  theme(axis.text.x=element_blank(),
        axis.text.y=element_blank()) +
  scale_colour_gradient(low = "grey", high = "red", na.value = NA) +
  scale_fill_gradient(low = "grey", high = "red", na.value = NA) +
  ggsave("plots/map_province.png", width = 6, height=2)
