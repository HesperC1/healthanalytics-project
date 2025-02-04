packages <- c("dplyr", "ggplot2", "tidyr", "corrplot", "ggcorrplot", "car", "survey", "ipumsr")
package.check <- lapply(packages, function(x) {
  if (!require(x, character.only = TRUE)) {
    install.packages(x, dependencies = TRUE)
    library(x, character.only = TRUE)
  }
})


# Load data
ddi <- read_ipums_ddi("nhis_00005.xml")
data <- read_ipums_micro(ddi)

# View first few rows of the dataset
data_clean <- data %>%
  dplyr::select(AGE, SEX, PSU, STRATA, PERWEIGHT, INCFAM07ON, INCFAM97ON2, HEALTH, EDUCREC1, NCHILD, EMPSTATIMP1, CIGDAYMO, CIGSDAY, HRSLEEP, SLEEPFALL, SLEEPSTAY, 
                AHOPELESS, ANERVOUS, ARESTLESS, ASAD, AWORTHLESS, AEFFORT) %>%
  filter(AGE >= 18, CIGSDAY <= 20, INCFAM07ON < 90, SLEEPSTAY < 90, SLEEPFALL < 90,
         AHOPELESS < 6, ANERVOUS < 6, ARESTLESS < 6, ASAD < 6, AWORTHLESS < 6, AEFFORT < 6, HEALTH<6, EMPSTATIMP1!=0, INCFAM07ON<96, INCFAM97ON2<97)


#write.csv(data_clean, file = "~/Desktop/data_clean.csv", row.names = FALSE)
# 🔹 计算 K6 变量
data_clean <- data_clean %>%
  mutate(K6 = AHOPELESS + ANERVOUS + ARESTLESS + ASAD + AWORTHLESS + AEFFORT)

# 🔹 相关性分析
cor_test <- cor.test(data_clean$CIGSDAY, data_clean$K6, use = "complete.obs")
print(cor_test)

# 🔹 可视化 CIGSDAY 与 K6 的关系
ggplot(data_clean, aes(x = CIGSDAY, y = K6)) +
  geom_point(alpha = 0.5, color = "blue") +
  geom_smooth(method = "lm", color = "red", se = TRUE) +
  labs(title = "Cigarettes Per Day vs. Psychological Distress (K6)",
       x = "Cigarettes per Day", y = "K6 Score") +
  theme_minimal()


# 🔹 线性回归模型
lm_model <- lm(K6 ~ CIGSDAY, data = data_clean)
summary(lm_model)


# 🔹 非线性回归模型
lm_model_quad <- lm(K6 ~ CIGSDAY + I(CIGSDAY^2), data = data_clean)
summary(lm_model_quad)

# 🔹 多元回归分析（控制变量）
lm_model_multi <- lm(K6 ~ CIGSDAY + AGE + SEX + INCFAM07ON + HRSLEEP + SLEEPFALL + SLEEPSTAY, data = data_clean)
summary(lm_model_multi)

# 🔹 VIF 多重共线性检查
library(car)
vif(lm_model_multi)

# 🔹 加权回归分析（如果数据涉及抽样权重）
library(survey)
design <- svydesign(
  ids = ~PSU,         # 聚类变量 (Primary Sampling Unit)
  strata = ~STRATA,   # 分层变量 (Stratification)
  weights = ~PERWEIGHT,  # 加权变量
  data = data_clean,
  nest = TRUE  # 如果数据有嵌套抽样，使用 nest=TRUE
)

design <- svydesign(ids = ~1, weights = ~PERWEIGHT, data = data_clean)

weighted_model <- svyglm(K6 ~ CIGSDAY + AGE + SEX + HEALTH + NCHILD + INCFAM07ON + HRSLEEP + SLEEPFALL + SLEEPSTAY,
                         design = design)
summary(weighted_model)

# 计算整个模型的 F 统计量
f_test <- regTermTest(weighted_model, ~ CIGSDAY + AGE + SEX + HEALTH + NCHILD + INCFAM07ON + HRSLEEP + SLEEPFALL + SLEEPSTAY)
print(f_test)

# R-squared
y_hat <- predict(weighted_model, type = "response")
y <- data_clean$K6
w <- weights(design)
sst <- sum(w * (y - weighted.mean(y, w))^2)
sse <- sum(w * (y - y_hat)^2)
R2_weighted <- 1 - (sse / sst)
print(R2_weighted)

# 异方差检验， 🔹 1. Breusch-Pagan 检验（BP 检验）， 运行 Breusch-Pagan 检验，
#p 值 < 0.05：存在异方差问题。
#p 值 > 0.05：未发现显著的异方差问题。

library(lmtest)
bp_test <- bptest(weighted_model) 
print(bp_test)


# 🔹 2. White 检验，（t 值和 p 值不同于原模型），说明异方差对结果有影响。
library(sandwich)
library(lmtest)

# 计算 White 异方差稳健标准误
white_se <- vcovHC(weighted_model, type = "HC")

# White 检验（基于稳健标准误的 F 检验）
white_test <- coeftest(weighted_model, vcov = white_se)
print(white_test)



# 3. 画出残差图（Residual Plot）如果点均匀分布，无系统性模式，说明同方差成立。如果点呈现漏斗状或其他系统性变化，说明存在异方差问题。
library(ggplot2)

# 计算加权回归（WLS）残差
data_clean$residuals_wls <- residuals(weighted_model)
data_clean$fitted_wls <- fitted(weighted_model)

# 绘制残差图
ggplot(data_clean, aes(x = fitted_wls, y = residuals_wls)) +
  geom_point(alpha = 0.5, color = "blue") +  # 绘制残差点
  geom_smooth(method = "loess", color = "red", se = FALSE) +  # 添加 LOESS 平滑曲线
  labs(title = "Residual Plot for Weighted Least Squares (WLS)",
       x = "Fitted Values",
       y = "Residuals") +
  theme_minimal()


# 重新计算回归模型并使用稳健标准误
robust_model <- coeftest(lm_model_multi, vcov = vcovHC(lm_model_multi, type = "HC"))
print(robust_model)


#robustness check1
# 1️⃣ 仅包含核心变量（基准模型）
model_1 <- svyglm(K6 ~ CIGSDAY, design = design)
summary(model_1)
# 2️⃣ 加入基本的人口统计变量
model_2 <- svyglm(K6 ~ CIGSDAY + AGE + SEX, design = design)
summary(model_2)
# 3️⃣ 加入健康和家庭相关变量
model_3 <- svyglm(K6 ~ CIGSDAY + AGE + SEX + HEALTH + NCHILD, design = design)
summary(model_3)
# 4️⃣ 加入经济变量
model_4 <- svyglm(K6 ~ CIGSDAY + AGE + SEX + HEALTH + NCHILD + INCFAM07ON, design = design)
summary(model_4)
# 5️⃣ 加入睡眠相关变量（完整模型）
model_5 <- svyglm(K6 ~ CIGSDAY + AGE + SEX + HEALTH + NCHILD + INCFAM07ON + HRSLEEP + SLEEPFALL + SLEEPSTAY, design = design)
summary(model_5)

