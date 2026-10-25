# Test documents: answer key

Five realistic sample documents for the build-plan task "Try five real documents and fix what misreads". Each has planted mistakes and fine-print traps. All names and companies are made up.

**To use one:** drag its photo from `props/photos/` onto the Grasp canvas (or press ⌘O), or open the `.html` in a browser, print it and photograph it with the phone. Then hover the numbers and ask the questions below (make a fist, or press ⌘K).

There are two kinds of problems:
- **Catches** are in the fine print. Grasp's reader is asked to find these, so they should show in red on the card.
- **Mistakes** are numbers that don't add up. Grasp finds these by itself: the reader lists the page's arithmetic and Swift redoes it, so each one shows first on the card as "Doesn't add up". Ask ("Does the total add up?") for the details.

---

## 1. Phone bill · `phone-bill.html`

Northway Mobile monthly statement, total due **$145.32**.

**Mistakes**
| What's wrong | On the bill | Should be |
|---|---|---|
| Charges don't add up to the total | $145.32 | $135.32 (the −$10 AutoPay discount was never subtracted) |
| Promo price not applied | Plan $85.00 | $60.00 (promo runs through Jun 2027) |
| Late fee on an on-time payment | $7.00 | $0 (paid Oct 1, due Oct 3) |

**Catches:** Device Protection Plus ($15/mo) added Sep 28, likely not asked for; two "recovery" fees ($3.49 and $2.99) that are Northway's own charges, not taxes; the remaining device balance ($800) comes due if you leave.

A fair bill is **$88.32** without the protection add-on, or $103.32 with it.

**Ask:** "Do the charges add up?" · "Why is my plan $85 when I have a promo?" · "Was I charged a late fee unfairly?" · "What could I get taken off?"

---

## 2. Apartment lease · `apartment-lease.html`

Maple Court Apartments, 12 months at **$1,150** rent.

**Mistakes**
| What's wrong | On the lease | Should be |
|---|---|---|
| Total rent for the term | $14,400.00 | $13,800.00 (12 × $1,150) |

**Catches:**
- **Auto-renews** for 12 more months unless you give 60 days' written notice, with up to **8%** more rent.
- **Leaving early** costs 2 months' rent ($2,300) **plus the whole $1,500 deposit**.
- **$300 cleaning** is taken from the deposit no matter how clean you leave it.
- You pay any repair under $250, **including their appliances**.
- **Late fee:** 10% of rent ($115) after the 3rd, then $25 a day.
- **Joint liability:** you can be charged your roommate's full share.
- **Required fees:** $53 a month on top of rent ($636 a year).

**The real year:** 12 × $1,203 = $14,436, plus $310 in non-refundable fees and the $300 cleaning charge, is **$15,046**.

**Ask:** "How much will this lease really cost me for the year?" · "What happens if I need to move out early?" · "How do I stop it from renewing?" · "Is the total rent right?"

---

## 3. Credit card offer · `credit-card-offer.html`

Ridgeline Bank Platinum Rewards, "0% intro APR" and "$0 annual fee".

**Mistakes (the headline contradicts the terms)**
| Headline says | The terms say |
|---|---|
| $0 annual fee | $0 the first year, **then $95** |
| 0% intro APR | **Deferred interest:** if the promo balance isn't paid in full in 12 months, interest is charged **from the purchase date** at 24.99% to 29.99% |

**Catches:**
- **Penalty APR** of 29.99% after a single late payment, and it **may apply indefinitely**.
- **Payments go to the lowest-APR balance first**, so higher-rate balances keep growing.
- **Fees:** 5% on balance transfers and cash advances, 3% on foreign transactions.
- **Rewards:** points expire after 24 months.
- **Credit check:** "pre-approved" still means a hard inquiry.

**Ask:** "Is it really 0% interest?" · "Is there an annual fee?" · "If I owe $2,000 at 29.99% and pay $50 a month, how long until it's paid off?"

That last one is a strong demo moment. Grasp should use its `payoff_months` tool and answer **325 months (27 years) and $14,218 in interest**, because $50 barely covers the monthly interest. At $100 a month it's 29 months and $807.

---

## 4. Pay stub · `pay-stub.html`

Valley State University student job, net pay **$340.00**.

**Mistakes**
| What's wrong | On the stub | Should be |
|---|---|---|
| Hours × rate | 32.50 × $13.50 = $425.25 | **$438.75** (one hour's pay, $13.50, missing) |
| Social Security at 6.2% | $28.37 | $26.37 on $425.25 (6.2% × 425.25) |

**Catches:**
- **Student FICA exception:** a full-time student working for their own university is usually exempt from Social Security and Medicare. The stub's own fine print says so. That's $34.54 this period and $161.01 so far this year.
- **Uniform charge:** $15 is taken every pay period until $90 is repaid.

**Ask:** "Was I paid right for my hours?" · "Should Social Security be taken out of my pay?" · "How much was I underpaid?"

---

## 5. Financial aid letter · `financial-aid-letter.html`

Valley State University 2027–28 offer: "$28,300 in aid · $0 remaining · You're fully covered!"

**Mistakes**
| What's wrong | On the letter | Should be |
|---|---|---|
| Total direct cost | $26,000 | **$26,500** ($15,200 + $7,400 + $3,900) |
| "You're fully covered" | $0 remaining | Only **$11,300 is free money**; $14,500 is loans and $2,500 is work-study paid as wages |

**What it really costs:** $26,500 billed − $11,300 grants = **$15,200** still owed for the year, before $3,100 of books and personal costs.

**Catches:**
- **Loans counted as aid:** $14,500, including a $9,000 **Parent PLUS** loan that your parent borrows.
- **Unsubsidized interest:** the Unsubsidized Loan builds interest while you're in school.
- **Work-study:** it isn't applied to your bill, and the job isn't guaranteed.
- **Merit scholarship:** it needs a **3.5 GPA** and 30 credits every year to renew.
- **Deadline pressure:** "accept by May 1 or it may be reduced".

**Ask:** "Am I really fully covered?" · "How much of this is free money?" · "How much will I actually owe this year?" · "Does the cost add up?"

---

## 6. A paper and someone's notes on it · `research-paper.html`, `paper-notes.html`

"Lids, Sleeves and the Cooling of Hot Drinks" (made-up data) and a student's handwritten-style notes. Read the paper first, then the notes: the notes turn into a card beside the paper.

| Note | Should be marked | Why |
|---|---|---|
| 1. k goes from 0.031 to 0.019 per minute | matches | Abstract |
| 2. With a lid it takes 25 minutes to reach 60 °C | differs | The paper says 30.0 minutes |
| 3. They ran 20 trials | differs | 12 trials per condition |
| 4. Room was kept at 21 °C | matches | Methods |
| 5. Ceramic cooled slower the whole time | differs | Ceramic lost heat faster for the first five minutes |
| 6. Stirring made it cool faster | not in the paper | They didn't stir |
| 7. Evaporation explains most of the lid effect | differs | Not measured; expected to explain "part" |
| 8. Sleeves don't matter | matches | "A sleeve made no measurable difference" |

**The paper's own math.** Every row of Table 1 follows Newton's law from 90 °C in a 21 °C room, time to 60 °C = ln(69/39)/k, except one planted mistake: **Ceramic, lid** has k = 0.017 per minute, which gives **33.6 minutes**, but the table says 25.9. The live model card should flag it.

**Directions** should grow from section 4: weigh the cup to measure evaporation, other fill volumes, double-walled cups, and lids with the drinking hole open or closed.

---

## 7. A lab protocol · `protocol.html`

"How much does a lid slow cooling?": 8 steps. Read it, then say "I'm starting the experiment" (or ⌘⇧G). Grasp should read these checks:

| Step | Grasp knows it's done when |
|---|---|
| 1. Place the cups, clip the probes | you say "done" |
| 2. Pour hot water into A | probe A jumps up |
| 3. Pour into B, lid on | probe B jumps up (on simulated probes, "done" pours and puts the lid on) |
| 4. Pour into C | probe C jumps up |
| 5. Wait until C is below 85 °C | probe C reads under 85 |
| 6. Two ice cubes into C | probe C drops |
| 7. Leave everything for 2 minutes | a 2:00 timer |
| 8. Read out the final temperatures | you say "done" |

Saying "done" before the probe agrees is allowed, and it's noted as different from the page.

**The dispute (phone bill):** ⌘⇧W should come to **$42.00**: $10 (the total doesn't add up), $25 (promo not applied), $7 (late fee on an on-time payment). It should ask about the $15 protection plan and the $3.49 recovery fee without counting them.

---

## What to look for when you test

- **Catches show in red** on the document card, and hovering one shows the clause on the photo.
- **Hovering any number** shows the exact spot on the page.
- **Answers about the mistakes** use Swift's math (listed under "Grasp's math" on the answer card) and say the right corrected number.
- **The model line** makes sense: the lease and phone bill as monthly costs, the others as breakdowns or no model.

Note anything Grasp misses or gets wrong. That's the list to fix next.
