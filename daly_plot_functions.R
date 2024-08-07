
# setwd("~/Google Drive/My Drive/DALY impact of ACF 2024/ACF-impact-Rshiny/")
source("daly_estimator.R")

library(gridExtra)
library(kableExtra)
library(ggpattern)
library(magick)
library(MASS)
library(conflicted)
conflicted::conflict_prefer(name = "select", winner = "dplyr")
conflicted::conflict_prefer(name = "filter", winner = "dplyr")

plot_averages <- function(output_dalys_per_average_case = NULL, 
                          input_first_block = midpoint_estimates, 
                          number_labels = TRUE, ymax = NULL)
{
 
  if(missing(output_dalys_per_average_case)) 
    output_dalys_per_average_case <- dalys_per_average_case()
   
  plot <- ggplot(output_dalys_per_average_case %>% 
                   filter(cumulative_or_averted == "cumulative",
                                   average_or_detected == "average")  %>% 
                   mutate(component = case_when(str_detect(name, "mortality") ~ "TB Mortality",
                                                str_detect(name, "morbidity") ~ "TB Morbidity",
                                                str_detect(name, "sequelae") ~ "Post-TB Sequelae",
                                                str_detect(name, "transmission") ~ "Transmission")) %>%
                   mutate(ordered_component = fct_relevel(component, "Transmission", "Post-TB Sequelae", "TB Mortality", "TB Morbidity")),
                 aes(x=average_or_detected, y=value, fill=ordered_component)) +  
    geom_col(position = "stack", width = 1) +  
    theme_minimal() + xlab("") + ylab("DALYs") + ggtitle("Total DALYS generated per average case") + 
    guides(fill="none") +
    theme(axis.text.x = element_blank(),
          axis.ticks.x = element_blank(),
          panel.grid.major.x = element_blank(),
          panel.grid.minor.x = element_blank(),
          axis.text.y = element_text(size = 14),
          plot.title = element_text(size = 16))
    
  
  if (number_labels) plot <- plot + geom_text(aes(label = paste0  (ordered_component, ", ",round(value,2))),
                                              position = position_stack(vjust = .5), size=5) else
                                                plot <- plot + geom_text(aes(label = ordered_component),  
                                                                         position = position_stack(vjust = .5),
                                                                         size = 5)

  if (!is.null(ymax)) plot <- plot + ylim(0,ymax)
                                              
 return(plot)
}

plot_detectable_proportion <- function(averages_plot, estimates=midpoint_estimates)
{
  if(missing(averages_plot)) averages_plot <- plot_averages(dalys_per_average_case(estimates), number_labels = F)
  
  with(estimates, {
    detectable_period_plot <- 
      averages_plot + geom_rect(aes(xmin=0.5, xmax=0.5 + predetection_mm, ymin=0, 
                                  ymax= sum(averages_plot$data %>% filter(name!="transmission") %>% select(value))), 
                              fill="gray", alpha=0.3) + 
      geom_rect(aes(xmin=0.5, xmax= 0.5 + predetection_transmission,
                    ymin= sum(averages_plot$data %>% filter(name!="transmission") %>% select(value))), 
                ymax= sum(averages_plot$data %>% select(value)), 
                fill="gray", alpha=0.3) + 
      annotate(geom="text", x=0.5 + predetection_mm/2, y=0.1, 
               label="Accrues before detectability", angle=90, hjust=0) +
      geom_rect(aes(xmin=1.5 - postrx_mm, xmax=1.5, ymin=0, 
                    ymax= sum(averages_plot$data %>% filter(name!="transmission") %>% select(value))), 
                fill="gray", alpha=0.3) + 
      geom_rect(aes(xmin=1.5 - postrx_transmission, xmax= 1.5,
                    ymin= sum(averages_plot$data %>% filter(name!="transmission") %>% select(value))), 
                ymax= sum(averages_plot$data %>% select(value)), 
                fill="gray", alpha=0.3) + 
      annotate(geom="text", x=1.5 - postrx_mm/2, y=0.1, 
               label="Accrues after routine diagnosis", angle=90, hjust=0) + 
      ggtitle("Avertible DALYs per average case") +
      ylab("Cumulative DALYs")
    return(detectable_period_plot)
  } )
}

# plot_detectable_proportion()


plot_time_course <- function(within_case = NULL, estimates = midpoint_estimates)
{
  if(missing(within_case)) within_case <- within_case_cumulative_and_averted(estimates = estimates)

  plotdata <- rbind(within_case,
                    within_case %>% filter(cumulative_or_averted=="cumulative") %>%
                      mutate(cumulative_or_averted="detectable",
                             value = value*case_when(name=="transmission" ~ (1-estimates$predetection_transmission -    estimates$postrx_transmission),
                                                     TRUE ~ (1-estimates$predetection_mm - estimates$postrx_mm))),
                    within_case %>% filter(cumulative_or_averted=="cumulative") %>%
                      mutate(cumulative_or_averted="pre",
                             value = value*case_when(name=="transmission" ~ estimates$predetection_transmission,
                                                     TRUE ~ estimates$predetection_mm)),
                    within_case %>% filter(cumulative_or_averted=="cumulative") %>%
                      mutate(cumulative_or_averted="post",
                             value = value*case_when(name=="transmission" ~ estimates$postrx_transmission,
                                                     TRUE ~ estimates$postrx_mm)))
                   
  
  # If second half area is s fraction of total, with arbitrary detectable period width 2 (from -1 to +1) and midpoint height 1, 
  # then overall detectable area is 2;second half area is 2s;
  # ending height h2 is such that (h2+1)/2*1= 2s -> h2 = 4s - 1;
  # and initial height h1 of the first half is such that (h1+1)/2*1= 2-2s) --> h1 = 3 - 4s 
  
  h1_transmission <- 3 - 4 * estimates$second_half_vs_first_transmission
  h2_transmission <- 4 * estimates$second_half_vs_first_transmission - 1
  h1_mm <- 3 - 4 * estimates$second_half_vs_first_mm
  h2_mm <- 4 * estimates$second_half_vs_first_mm - 1
  
  # we're going to go around the polygon, first across the top. left to right, then bottom right to left. 
  # xs are defined by start of predetect for transmission and mm, then start/end of detectable, then end of post rx for transmission and mm. 
  # we'll define heights at each point (with bases at 0), then stack. 
  rect_points <- as_tibble(t(c("x1" = -1,
                               "x2" = -1,
                               "x3" = 1,
                               "x4" = 1)))
  
  rect_points <- rbind(rect_points %>% mutate(component = "morbidity"),
                       rect_points %>% mutate(component = "mortality"),
                       rect_points %>% mutate(component = "sequelae"),
                       rect_points %>% mutate(component = "transmission"))
                       
  
  rect_points <- rect_points %>% mutate(y1=0,
                                        y2=unlist(c(h1_mm, h1_mm, h1_mm, h1_transmission)*
                                                    (within_case %>% filter(cumulative_or_averted=="cumulative") %>% 
                                                     arrange(match(name, rect_points$component)) %>% select(value))),
                                        y3= unlist(c(h2_mm, h2_mm, h2_mm, h2_transmission)*
                                                     (within_case %>% filter(cumulative_or_averted=="cumulative") %>% 
                                                        arrange(match(name, rect_points$component)) %>% select(value))),
                                        y4=0)
  # now need to stack them
  rect_points_stacked <- rect_points %>% mutate(y2 = cumsum(y2), y3 = cumsum(y3)) %>%
                                          mutate(y1 = c(0, y2[1:3]), y4 = c(0, y3[1:3]))

  toplot <- rect_points_stacked %>%
    pivot_longer(-component,
                 names_to = c(".value", "id"),
                 names_pattern = "(\\D)(\\d+)") %>%
    mutate(component = factor(component, levels = rev(c("morbidity","mortality", "sequelae", "transmission"))))

  # make gradient of x shadings for "before dectectability" rectangle
  n <- 1000
  x_steps <- seq(from = min(rect_points_stacked$x1), to = 1.4*min(rect_points_stacked$x1), length.out = n + 1)
  alpha_steps <- seq(from = 0.3, to = 0, length.out = n)
  rect_grad <- data.frame(xmin = x_steps[-(n + 1)], 
                          xmax = x_steps[-1], 
                          alpha = alpha_steps,
                          ymin = 0,
                          ymax = max(rect_points_stacked$y3))

  time_course_plot <- ggplot(data = toplot) +
    geom_polygon(aes(x = x, y = y, group = component, fill = component)) +
    scale_fill_discrete(breaks = rev(levels(toplot$component))) +
    xlab("Time during detectable period") +
    ylab("DALY accrual rate (arbitrary scale)") +
    scale_x_discrete(labels = NULL, breaks = NULL) +
    scale_y_discrete(labels = NULL, breaks = NULL) +
    theme_minimal() +
    geom_rect(data=rect_grad, 
              aes(xmin=xmin, xmax=xmax,
                  ymin=ymin, ymax=ymax, 
                  alpha=alpha), fill="gray") + 
    guides(alpha = "none") + 
    geom_vline(data = rect_points_stacked, aes(xintercept = min(x4))) +
    annotate(geom = "text", x = 1.15 * max(rect_points_stacked$x1), y = max(rect_points_stacked$y4) / 2,
             label = "before detectability", angle = 90, size=4, fontface = "italic") +
    annotate(geom = "text", x = 1.08 * min(rect_points_stacked$x4), y = max(rect_points_stacked$y4) / 2,
             label = "after routine detection", angle = 90, size=4, fontface = "italic") +
    guides(fill = guide_legend(reverse = TRUE)) +
    ggtitle("Timing of DALY accrual") +
    theme(axis.text = element_text(size = 16),
          plot.title = element_text(size = 16),
          legend.position = "inside",
          legend.position.inside = c(.4,.7)) + 
    # at top of plot, add horizontal arrows from o to 1 and from 0 to -1
     annotate("segment", x = 0.04, y = max(rect_points_stacked$y3), xend = 1, yend = max(rect_points_stacked$y3), 
         linejoin = "mitre", linewidth = 5, color = "gray40",
         arrow = arrow(type = "closed", length = unit(0.01, "npc"))) +
    annotate("text", x = 0.08, y = max(rect_points_stacked$y3), label = "More likely to avert", color = "white", 
         hjust = 0, size = 3) + 

    annotate("segment", x = -0.04, y = max(rect_points_stacked$y3), xend = -1, yend = max(rect_points_stacked$y3), 
         linejoin = "mitre", linewidth = 5, color = "gray40",
         arrow = arrow(type = "closed", length = unit(0.01, "npc"))) +
    annotate("text", x = -0.08, y = max(rect_points_stacked$y3), label = "Less likely to avert", color = "white", 
         hjust = 1, size = 3)

      
    return(time_course_plot)
}

# For manuscript, add lines showing potential timing of detection
fig3 <- plot_time_course() + 
  geom_vline(xintercept = 2/3, linetype = "dashed") + 
  geom_vline(xintercept = -2/3, linetype = "dotted") + 
  geom_vline(xintercept = 0, linetype = "dotdash") + 
  theme(legend.background = element_rect(fill = "white"),
          axis.title.y = element_text(vjust=-25),
          axis.title =  element_text(face = 'bold')) + 
  ggtitle("")
  

# As three vertically arranged panels, 
# Plot the distubion of probabilities of detection during cross-section screening 
# (corresponding to the duration of the detectable period),
# and then scatted plots showign the relationship between this duration and the 
# corresponding relative contributions to transmission and mortality. 

# Utility function: Gamma distribution version of the above function: for specified sd and mean,  get the shape and scale parameters.
solve_for_gamma_parameters <- function(mean, sd)
{
  shape <- mean^2 / sd^2
  scale <- sd^2 / mean
  return(list("shape" = shape, "scale" = scale))
}

# Illustrate covariance, assuming lognormal distirubtions with similar coefficient of variation for duration and mortality (and duration and transmission), and specified covariances.
plot_heterogeneity <- function(estimates = midpoint_estimates,
                               N = 500) # just for visualization, too few for stable estimates
{
  
  #  Y = exp(X) where X ~ N(mu, sigma)
  #  E[Y]_1 = 1 = exp(mu_1 + 1/2 sigma_11) ==> mu_1 + 1/2 sigma_11 = 0 ==> mu_1 = -1/2 sigma_11
  #  E[Y]_2 = 1 = exp(mu_2 + 1/2 sigma_22) ==> mu_2 = -1/2 sigma_22
  # cov_12^2 = cov_21^2 = exp(mu_1 + mu_2 + 1/2 sigma_11 + 1/2 sigma_jj) (exp(sigma_12) - 1) = 
  #  1*1*(exp(sigma_12) - 1) = exp(sigma_12) - 1 ==> 
  #  sigma_12 = log(cov_12^2 + 1)
  
  #  and we can choose nearly any sigma_ii's we want here. 
  # Suppose we choose sigma_11 = sigma_22 = 1.
  #  then m_1 = m_2 = -1/2, and sigma_12 = log(cov_12^2 + 1)
  # If sigma_11 = sigma_22 = 1. then correlation = covariance, and max cov is 1. 
  #  So let's set sigma_ii to ceiling(sqrt(covariance)) when cov is positive.

  simulate_correlated_variables <- function(covarianceA, covarianceB, sigma11 = NULL)
  { 
    if (covarianceA < -1/exp(1)) stop("Covariance must be at least -1/e this illustration using log-normals to work, although our DALY model is valid for covariances from -1 to infinity.")

    if(missing(sigma11)) sigma11 <- max(ceiling(sqrt(abs(covarianceA))),
                                        ceiling(sqrt(abs(covarianceB))),
                                        0.2)
    
    sigma22A <- max(ceiling(abs(covarianceA)/sigma11),0.2)
    sigma22B <- max(ceiling(abs(covarianceB)/sigma11),0.2)
    sigma12A <- log(covarianceA^2 + 1)
    sigma12B <- log(covarianceB^2 + 1)
    mu1 <- -1/2 * sigma11
    mu2A <- -1/2 * sigma22A 
    mu2B <- -1/2 * sigma22B
    sigma <- matrix(c(sigma11, sigma12A, sigma12B,  
                      sigma12A, sigma22A, 0,
                      sigma12B, 0, sigma22B), nrow=3)
    mu <- c(mu1, mu2A, mu2B)
    X <- mvrnorm(N, mu, sigma)
    Y <- exp(X)
    colnames(Y) <- c("Y1", "Y2", "Y3")
          
    return(Y)
  }

  # choose a sigma_11 for duration that works for both covariances:
  sigma_duration <- max(ceiling(sqrt(abs(estimates$covariance_mortality_duration))),
                        ceiling(sqrt(abs(estimates$covariance_transmission_duration))),
                        0.2)

  # change any out-of-range covariances to 0 and generate error flag
  covarianceA <- estimates$covariance_mortality_duration
  if (covarianceA < -1/exp(1))
  {
    covarianceA <- -1/exp(1)
    error_flag_mortality <- 1
  } else error_flag_mortality <- 0
  
  covarianceB <- estimates$covariance_transmission_duration
  if (covarianceB < -1/exp(1))
  {
    covarianceB <- -1/exp(1)
    error_flag_transmission <- 1
  } else error_flag_transmission <- 0

  MVN <- simulate_correlated_variables(covarianceA, covarianceB, sigma_duration)

  scatter1 <- 
    ggplot(data=MVN, aes(x=Y1, y=Y2)) + 
    geom_point(alpha=0.3, shape=16)  + 
    geom_rug(col=rgb(.5,0,0,alpha=.2)) + 
    theme_minimal() +
    theme(axis.text.x = element_blank(), axis.text.y = element_blank()) +
    geom_hline(yintercept = 1, linetype = "dashed") +
    annotate(geom = "text", x = 1, y = 0.1, 
      label = "Mean duration of detectable period", angle = 90, hjust = 0, vjust = -1) +
    geom_vline(xintercept = 1, linetype = "dashed") + 
    annotate(geom = "text", y = 1, x = 0.9, 
      label = "Mortality of the average case", angle = 0, hjust = -1, vjust = -1) +
    xlab("Relative duration \n(= relative probability of detection during ACF))") +
    ylab("Relative DALYs\nfrom TB mortality") +
    xlim(0, quantile(MVN[,"Y1"], 0.99)) +
    ylim(0, quantile(MVN[,"Y2"], 0.99))

  if(error_flag_mortality) scatter1 <- scatter1 +
  # add text on top of plot
    annotate(geom = "text", x = 1.1, y = 1.1,
      label = "Covariance too low for\nillustration with lognormals\n(but still valid for DALY model)",
      angle = 0, hjust = 0, vjust = 0, size=6, fontface="bold")
    
  scatter2 <- 
    ggplot(data=MVN, aes(x=Y1, y=Y3)) + 
    geom_point(alpha=0.3, shape=16)  + 
    geom_rug(col=rgb(.5,0,0,alpha=.2)) + 
    theme_minimal() +
    theme(axis.text.x = element_blank(), axis.text.y = element_blank()) +
    geom_hline(yintercept = 1, linetype = "dashed") +
    # annotate(geom = "text", x = 1, y = 0.1,
    #   label = "Mean duration of detectable period", angle = 90, hjust = 0, vjust = -1) +
    geom_vline(xintercept = 1, linetype = "dashed") + 
    annotate(geom = "text", y = 1, x = 0.9, 
      label = "Transmission from the average case", angle = 0, hjust = -1, vjust = -1) +
    xlab("Relative duration \n(= relative probability of detection during ACF))") +
    ylab("Relative DALYs\nfrom transmission") + 
    annotate(geom = "text", y = 1, x = 0.9, label = "Transmission from the average case", 
      angle = 0, hjust = -1, vjust = -1) + 
    xlim(0, quantile(MVN[,"Y1"], 0.99)) +
    ylim(0, quantile(MVN[,"Y3"], 0.99))

  if(error_flag_transmission) scatter2 <- scatter2 + 
  # add text on top of plot
    annotate(geom = "text", x = 1.1, y = 1.1, 
      label = "Covariance too low for\nillustration with lognormals\n(but still valid for DALY model)",
      angle = 0, hjust = 0, vjust = 0, size=6, fontface="bold")

  # Arrange the two figures in a column, with transmission first

  return(grid.arrange(scatter2, scatter1, ncol=1))

}

# plot_heterogeneity()


# Display a table of numerical estimates

output_table <- function(output, forsummary = 0)
{
  if (missing(output)) output <- daly_estimator()

  useoutput <- output %>% 
    pivot_wider(names_from = cumulative_or_averted, values_from = value) %>%
    pivot_wider(names_from = average_or_detected, values_from = c(cumulative, averted)) %>%
    mutate(name = str_to_title(name)) %>%
    bind_rows(summarise_all(., ~if(is.numeric(.)) sum(.) else "Total")) 

    if (forsummary==1) 
    outputtable <- useoutput %>% 
      select(name, cumulative_average, averted_detected) %>%
      kable(., format = "html",
          digits = 2,
          col.names=c("", "Total cumulative DALYs per case (average case)", "Averted by early detection (detected case)")) %>%
      kable_styling(bootstrap_options = c("striped", "hover"), full_width = FALSE) %>% 
      row_spec(5, bold = T, hline_after = T) else

    if (forsummary==2) 
    outputtable <- useoutput %>% 
      select(name, cumulative_average, averted_average, averted_detected) %>%
      kable(., format = "html",
          digits = 2,
          col.names=c("", "Total cumulative DALYs per case (average case)", "Averted by early detection (average case)", "Averted by early detection (detected case)")) %>%
      kable_styling(bootstrap_options = c("striped", "hover"), full_width = FALSE) %>% 
      row_spec(5, bold = T, hline_after = T) else

    if (forsummary==3) 
    outputtable <- useoutput %>% 
      kable(., format = "html",
          digits = 2,
          col.names=c("", "Total cumulative DALYs per case (average case)", "Total cumulative DALYs per case (detected case)", "Averted by early detection (average case)", "Averted by early detection (detected case)")) %>%
      kable_styling(bootstrap_options = c("striped", "hover"), full_width = FALSE) %>% 
      row_spec(5, bold = T, hline_after = T) else

    outputtable <- useoutput %>% 
    kable(., format = "html",
          col.names=c("Source", rep(c("Average incident case", "Average detected case"), times = 2)),
          digits = 2) %>%
    kable_styling(bootstrap_options = c("striped", "hover"), full_width = FALSE) %>%
    add_header_above(., header =
      c(" " = 1, "Total cumulative DALYs per case" = 2, "Averted by early detection" = 2)) %>% 
    row_spec(5, bold = T, hline_after = T)

return(outputtable)
}

# output_table()

# Now a figure similar to plot_averages() but showing DALYs averted per case detected, using the "Averted by early detection, Average detected case" from table above. 


plot_averted <- function(output, number_labels = TRUE, ymax = NULL)
{
 
  if(missing(output)) output <- daly_estimator()
   
  plot <- ggplot(output %>% filter(cumulative_or_averted == "averted",
                                   average_or_detected == "detected")  %>% 
                   mutate(component = case_when(str_detect(name, "mortality") ~ "TB Mortality",
                                                str_detect(name, "morbidity") ~ "TB Morbidity",
                                                str_detect(name, "sequelae") ~ "Post-TB Sequelae",
                                                str_detect(name, "transmission") ~ "Transmission")) %>%
                   mutate(ordered_component = fct_relevel(component, "Transmission", "Post-TB Sequelae", "TB Mortality", "TB Morbidity")),
                 aes(x=average_or_detected, y=value, fill=ordered_component)) +  
    geom_col(position = "stack", width = 1) +  
    theme_minimal() + xlab("") + ylab("DALYs") + ggtitle("DALYS averted per case detected") + 
    guides(fill="none") +
    theme(axis.text.x = element_blank(),
          axis.ticks.x = element_blank(),
          panel.grid.major.x = element_blank(),
          panel.grid.minor.x = element_blank(),
          axis.text.y = element_text(size = 14),
          plot.title = element_text(size = 16))
    
  
  if (number_labels) plot <- plot + geom_text(aes(label = paste0  (ordered_component, ", ",round(value,2))),
                                              position = position_stack(vjust = .5)) else
                                                plot <- plot + geom_text(aes(label = ordered_component),
                                                                         position = position_stack(vjust = .5))

  if (!is.null(ymax)) plot <- plot + ylim(0,ymax)
                                              
 return(plot)
}

# plot_averted()


plot_averted_portion <- function(output, ymax = NULL, base = "detected")
{
 
  if(missing(output)) output <- daly_estimator()
   
  plot <- ggplot(output %>% filter(average_or_detected == base)  %>% 
                   mutate(component = case_when(str_detect(name, "mortality") ~ "TB Mortality",
                                                str_detect(name, "morbidity") ~ "TB Morbidity",
                                                str_detect(name, "sequelae") ~ "Post-TB Sequelae",
                                                str_detect(name, "transmission") ~ "Transmission")) %>%
                  pivot_wider(names_from = "cumulative_or_averted", values_from = "value") %>%
                  mutate(difference = cumulative - averted) %>%
                  pivot_longer(cols = c("cumulative", "averted", "difference"), names_to = "cumulative_or_averted", values_to = "value") %>%
                  filter(cumulative_or_averted != "cumulative") %>%
                  mutate(ordered_component = fct_relevel(component, "Transmission", "Post-TB Sequelae", "TB Mortality", "TB Morbidity")),
                  
                   # make a stacked bar plot of "cumulative", and shade the "averted" portion of each in gray
                aes(x=average_or_detected, y=value, fill=ordered_component, pattern = cumulative_or_averted)) +
          geom_col_pattern(position = "stack", width = 1,
            pattern_fill = 'black',  pattern_spacing = 0.015) +
          scale_pattern_manual(name = "Averted by early detection?", 
                               values = c("stripe", "none"), 
                               breaks = c("averted", "difference"),
                               labels = c("Averted", "Not averted")) +
        theme_minimal() + xlab("") + ylab("DALYs") + 
        guides(fill="none") +
        theme(axis.text.x = element_blank(),
          axis.ticks.x = element_blank(),
          panel.grid.major.x = element_blank(),
          panel.grid.minor.x = element_blank(),
          axis.text.y = element_text(size = 14),
          plot.title = element_text(size = 16),
          legend.position = "bottom")

    
  if (base == "detected") plot <- plot + ggtitle("DALYs per *detected* case") else
    plot <- plot + ggtitle("DALYS per *average* case")
  
  if (!is.null(ymax)) plot <- plot + ylim(0,ymax)
                                              
 return(plot)
}

plot_averted_portion()
