"""Employers whose public job boards are read. Every entry was checked against the live
board (October 2026) and had open roles in India. Add a company: find its careers page,
see which board it uses (the job links show greenhouse.io / lever.co / ashbyhq.com),
and add the board name and the company's token from those links.
"""

from typing import NamedTuple


class Board(NamedTuple):
    kind: str  # greenhouse | lever | ashby
    token: str  # the company's id in the board's links
    company: str  # how the app shows it


BOARDS: list[Board] = [
    Board("lever", "paytm", "Paytm"),
    Board("lever", "meesho", "Meesho"),
    Board("lever", "zeta", "Zeta"),
    Board("lever", "mindtickle", "MindTickle"),
    Board("lever", "netomi", "Netomi"),
    Board("lever", "cred", "CRED"),
    Board("greenhouse", "razorpaysoftwareprivatelimited", "Razorpay"),
    Board("greenhouse", "groww", "Groww"),
    Board("greenhouse", "inmobi", "InMobi"),
    Board("greenhouse", "glance", "Glance"),
    Board("greenhouse", "hackerrank", "HackerRank"),
    Board("greenhouse", "druva", "Druva"),
    Board("greenhouse", "okta", "Okta"),
    Board("greenhouse", "databricks", "Databricks"),
    Board("greenhouse", "mongodb", "MongoDB"),
    Board("greenhouse", "stripe", "Stripe"),
    Board("greenhouse", "zetaglobal", "Zeta Global"),
    Board("greenhouse", "gitlab", "GitLab"),
    Board("greenhouse", "rubrik", "Rubrik"),
    Board("greenhouse", "elastic", "Elastic"),
    Board("greenhouse", "twilio", "Twilio"),
    Board("greenhouse", "datadog", "Datadog"),
    Board("greenhouse", "coinbase", "Coinbase"),
    Board("greenhouse", "airbnb", "Airbnb"),
    Board("greenhouse", "figma", "Figma"),
    Board("ashby", "sarvam", "Sarvam AI"),
    Board("ashby", "atlan", "Atlan"),
    Board("ashby", "notion", "Notion"),
]
