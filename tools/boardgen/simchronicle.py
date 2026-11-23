"""Ten days of play for the sim's chronicle: entries (handed-in quests) and the days' ledgers, as Lua to run in the sim."""
import random, json, sys, time as pytime, datetime
random.seed(7)
NOW = int(sys.argv[1])
QUESTS = [(843,23,5006,3392),(846,26,5017,3376),(849,26,None,None),(851,18,5023,3395),(852,19,5025,3396),(858,18,5050,3445),(863,18,None,None),
          (865,18,5055,3256),(868,22,5058,None),(873,27,5104,3476),(874,27,None,None),(876,20,5067,3452),(878,21,None,None),(879,25,5074,3436),
          (882,19,5101,3257),(883,22,None,None),(884,24,None,None),(885,25,None,None),(893,24,5093,3456),(896,18,5097,3283),(897,24,None,None),
          (899,20,5085,3258),(906,25,None,None),(907,18,5143,3238),(913,20,5164,3247),(1058,26,5582,4020),(1060,20,None,None),(1068,23,None,None),
          (1087,25,None,None),(1088,29,5686,4273),(1090,22,None,None),(1092,22,None,None),(1093,21,5734,3988),(1095,27,None,None),(1096,27,5736,4202),
          (1104,30,5794,4139),(1105,30,5795,4142),(1149,26,None,None),(1150,30,5843,4490),(1151,30,5844,4499),(1152,30,None,None),(1153,29,5842,4113),
          (1159,30,None,None),(1176,30,5848,4154),(3369,25,None,None),(4542,25,None,None),(4770,29,None,None),(4841,25,None,None),(4865,26,None,None)]
GREENS = [1077, 1462, 1187, 2944, 4766]
BLUES = [2236, 4196, 4320, 6468, 2194]
CREATURES = [3272, 3273, 3275, 3256, 3394, 3255, 3254]
HERBS, ORE = [2447, 765, 785, 2450, 2452, 3355], [2770, 2771]
PLAN = [(9, 25, 26), (8, 26, 27), (6, 27, 27), (5, 27, 28), (4, 28, 28), (2, 28, 29), (1, 29, 29), (0, 29, 30)]  # days ago, level from, to

today = datetime.datetime.fromtimestamp(NOW).date()
entries, days, quest_index = [], {}, 0
for ago, level_from, level_to in PLAN:
    date = today - datetime.timedelta(days=ago)
    key = date.isoformat()
    noon = int(datetime.datetime(date.year, date.month, date.day, 12).timestamp())
    played = random.randint(5400, 13500) if ago else 10260
    day = {"played": played, "levelFrom": level_from, "gold": {}, "spent": {}, "xp": {}}
    if level_to > level_from:
        day["levelTo"] = level_to
    count = random.randint(5, 7)
    start = noon - 3 * 3600 + random.randint(0, 3600)
    quest_xp = quest_money = 0
    for n in range(count):
        if quest_index >= len(QUESTS):
            break
        questId, qlevel, itemId, npcId = QUESTS[quest_index]
        quest_index += 1
        xp = qlevel * random.randint(70, 110)
        money = random.choice([0, qlevel * 25, qlevel * 60, qlevel * 90])
        duration = random.randint(240, 2600)
        turned = start + int(played * (n + 1) / (count + 1))
        entry = {"questId": questId, "playerLevel": level_from if n < count - 1 else level_to, "acceptedAt": turned - duration - 600,
                 "turnedInAt": turned, "duration": duration, "experience": xp}
        if money:
            entry["money"] = money
        if random.random() < 0.15:
            entry["deaths"] = 1
        if random.random() < 0.3:
            entry["wasGrouped"] = True
        if random.random() < 0.25:
            entry["rewardItemId"] = random.choice(GREENS)
        if itemId and npcId:
            drops = random.randint(4, 10)
            chance = random.choice([0.2, 0.3, 0.45, 0.6])
            expected = round(drops / chance, 1)
            kills = max(drops, int(expected * random.uniform(0.6, 1.6)))
            entry["drops"] = [{"itemId": itemId, "drops": drops, "kills": kills, "expected": expected, "killsByNpcId": {npcId: kills}}]
        entries.append(entry)
        quest_xp += xp
        quest_money += money
    day["quests"] = count
    day["gold"] = {"quests": quest_money, "looted": random.randint(8000, 26000), "vendor": random.randint(9000, 36000)}
    if random.random() < 0.5:
        day["gold"]["auction"] = random.randint(15000, 60000)
    if random.random() < 0.3:
        day["gold"]["other"] = random.randint(200, 2000)
    day["spent"] = {"repairs": random.randint(800, 4200), "bought": random.randint(300, 2600)}
    if level_to > level_from:
        day["spent"]["training"] = random.randint(6000, 11000)
    if random.random() < 0.6:
        day["spent"]["flights"] = random.randint(400, 1500)
    kills_xp = random.randint(9000, 19000)
    rested = random.randint(0, 6000)
    day["xp"] = {"quests": quest_xp, "kills": kills_xp, "rested": rested, "discovery": random.choice([0, 340, 680, 1340])}
    day["xp"] = {k: v for k, v in day["xp"].items() if v}
    day["kills"] = random.randint(90, 320)
    if random.random() < 0.4:
        day["deaths"] = random.randint(1, 2)
    day["chests"] = random.randint(0, 3)
    day["nodes"] = random.randint(0, 9)
    if day["nodes"]:
        day["gathered"] = {i: random.randint(1, 6) for i in random.sample(HERBS + ORE, 3)}
    loot = []
    for _ in range(random.randint(1, 4)):
        loot.append({"itemId": random.choice(GREENS), "from": random.choice(CREATURES + ["chest"])})
    if random.random() < 0.5:
        loot.append({"itemId": random.choice(BLUES), "from": random.choice(CREATURES)})
    day["loot"] = loot
    for part in ("gold", "spent", "xp"):
        day[part] = {k: v for k, v in day[part].items() if v}
    days[key] = {k: v for k, v in day.items() if v not in (0, {}, [])}

def lua(value):
    if isinstance(value, dict):
        return "{" + ",".join(f"[{json.dumps(k) if isinstance(k, str) else k}]={lua(v)}" for k, v in value.items()) + "}"
    if isinstance(value, list):
        return "{" + ",".join(lua(v) for v in value) + "}"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value)
    return repr(value)

total_played = sum(d["played"] for d in days.values())
code = ("local book = OneMoreQuestDB.chronicle and OneMoreQuestDB.chronicle['Simmy-Simland'] "
        "if not book then OneMoreQuestDB.chronicle = OneMoreQuestDB.chronicle or {} book = {} OneMoreQuestDB.chronicle['Simmy-Simland'] = book end "
        f"book.entries = {lua(entries)} book.days = {lua(days)} book.playedSeconds = {total_played} book.startedAt = {NOW - 10 * 86400} "
        "book.abandonedCount = 3 book.open = book.open or {} "
        f"return #book.entries .. ' entries, ' .. {len(days)} .. ' days'")
print(code)
