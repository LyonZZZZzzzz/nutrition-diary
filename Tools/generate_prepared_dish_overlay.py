#!/usr/bin/env python3
"""Generate the versioned Chinese prepared-dish recipe overlay."""
from __future__ import annotations

import json
import pathlib
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]
SEEDS = ROOT / "Packages/NutritionKit/Sources/NutritionKit/Resources/SeedFoods.json"
OUTPUT = ROOT / "CatalogData/ChinesePreparedDishOverlay.json"
NAMESPACE = uuid.UUID("c337fece-a32d-5d7a-bc2b-4d72af4f26f1")

seed_file = json.loads(SEEDS.read_text())
food_ids = {food["name"]: food["uuid"] for food in seed_file["foods"]}
categories = {
    "炒菜": "Chinese stir-fry",
    "炖煮": "Chinese braised dish",
    "主食": "Chinese staple",
    "汤羹": "Chinese soup",
    "早餐": "Chinese breakfast",
    "凉菜": "Chinese cold dish",
    "咖啡奶茶": "Coffee and milk tea",
    "甜品": "Dessert and snack",
}

def ing(name: str, grams: float, unit: str = "g") -> dict:
    if name not in food_ids:
        raise ValueError(f"unknown seed ingredient: {name}")
    return {"foodUUID": food_ids[name], "amount": grams, "unit": unit}

def dish(name, en, pinyin, aliases, category, weight, ingredients, portion="1份", aliases_en=None):
    return {
        "id": str(uuid.uuid5(NAMESPACE, name)),
        "nameZh": name,
        "nameEn": en,
        "pinyin": [pinyin, pinyin.replace(" ", "")],
        "aliasesZh": aliases,
        "aliasesEn": aliases_en or [],
        "categoryZh": category,
        "categoryEn": categories[category],
        "preparationState": "prepared",
        "finalYieldGrams": weight,
        "servings": [{"label": portion, "amount": weight, "unit": "g", "approximate": True}],
        "ingredients": ingredients,
        "source": {
            "title": "NutritionDiary Chinese prepared dish recipe",
            "license": "Curated internal recipe based on licensed ingredient data",
            "url": None,
            "retrievedAt": "2026-10-19T00:00:00Z",
        },
    }

D = []
# 50 stir-fry / home dishes
D += [
 dish("宫保鸡丁","Kung Pao Chicken","gong bao ji ding",["宫爆鸡丁","宫保鸡"],"炒菜",300,[ing("鸡胸肉",150),ing("彩椒",60),ing("洋葱",30),ing("葱",15),ing("生抽酱油",15),ing("白砂糖",8),ing("米醋",8),ing("植物油",15),ing("大蒜",8)]),
 dish("鱼香肉丝","Yu Xiang Shredded Pork","yu xiang rou si",["鱼香猪肉丝","余香肉丝"],"炒菜",330,[ing("猪里脊",150),ing("彩椒",60),ing("胡萝卜",50),ing("蘑菇",30),ing("生抽酱油",15),ing("白砂糖",10),ing("米醋",10),ing("植物油",15),ing("大蒜",8)]),
 dish("番茄炒蛋","Tomato Scrambled Eggs","fan qie chao dan",["西红柿炒鸡蛋","番茄炒鸡蛋","西红柿炒蛋"],"炒菜",330,[ing("鸡蛋",120),ing("番茄",220),ing("葱",10),ing("白砂糖",5),ing("植物油",15)]),
 dish("青椒肉丝","Green Pepper Shredded Pork","qing jiao rou si",["尖椒肉丝","青椒猪肉丝"],"炒菜",300,[ing("猪里脊",150),ing("彩椒",150),ing("生抽酱油",15),ing("植物油",15),ing("大蒜",5)]),
 dish("麻婆豆腐","Mapo Tofu","ma po dou fu",["麻辣豆腐"],"炒菜",380,[ing("北豆腐",300),ing("猪里脊",60),ing("辣椒酱",20),ing("葱",10),ing("植物油",15),ing("生抽酱油",10)]),
 dish("红烧肉","Red Braised Pork","hong shao rou",["家常红烧肉"],"炖煮",300,[ing("猪里脊",250),ing("白砂糖",15),ing("生抽酱油",20),ing("生姜",10),ing("植物油",10)]),
 dish("回锅肉","Twice-Cooked Pork","hui guo rou",["回锅猪肉"],"炒菜",380,[ing("猪里脊",200),ing("卷心菜",150),ing("彩椒",30),ing("生抽酱油",15),ing("辣椒酱",15),ing("植物油",10)]),
 dish("糖醋里脊","Sweet and Sour Pork","tang cu li ji",["糖醋猪肉","糖醋里肌肉"],"炒菜",300,[ing("猪里脊",200),ing("白砂糖",25),ing("米醋",20),ing("生抽酱油",10),ing("玉米淀粉",30),ing("植物油",20)]),
 dish("京酱肉丝","Jing Sauce Shredded Pork","jing jiang rou si",["京酱猪肉丝"],"炒菜",300,[ing("猪里脊",180),ing("葱",80),ing("生抽酱油",20),ing("白砂糖",10),ing("植物油",10)]),
 dish("木须肉","Moo Shu Pork","mu xu rou",["木樨肉","木须猪肉"],"炒菜",400,[ing("猪里脊",150),ing("鸡蛋",100),ing("黄瓜",100),ing("蘑菇",50),ing("生抽酱油",10),ing("植物油",15)]),
 dish("蒜苔肉丝","Garlic Scape Shredded Pork","suan tai rou si",["蒜苔炒肉","蒜薹肉丝"],"炒菜",300,[ing("猪里脊",150),ing("四季豆",150),ing("生抽酱油",10),ing("植物油",15)]),
 dish("芹菜肉丝","Celery Shredded Pork","qin cai rou si",["芹菜炒肉"],"炒菜",300,[ing("猪里脊",150),ing("芹菜",150),ing("生抽酱油",10),ing("植物油",15)]),
 dish("洋葱炒牛肉","Onion Beef Stir-Fry","yang cong chao niu rou",["洋葱牛肉"],"炒菜",320,[ing("牛里脊",160),ing("洋葱",150),ing("生抽酱油",15),ing("植物油",15)]),
 dish("西兰花炒牛肉","Beef and Broccoli","xi lan hua chao niu rou",["西兰花牛肉","牛肉炒西兰花"],"炒菜",360,[ing("牛里脊",150),ing("西兰花",200),ing("生抽酱油",15),ing("植物油",15)]),
 dish("黑椒牛柳","Black Pepper Beef","hei jiao niu liu",["黑椒牛肉","黑胡椒牛柳"],"炒菜",350,[ing("牛里脊",180),ing("洋葱",100),ing("彩椒",80),ing("生抽酱油",10),ing("植物油",15)]),
 dish("香菇鸡片","Chicken with Mushrooms","xiang gu ji pian",["香菇鸡肉片","蘑菇炒鸡"],"炒菜",320,[ing("鸡胸肉",150),ing("蘑菇",120),ing("彩椒",50),ing("生抽酱油",10),ing("植物油",15)]),
 dish("辣子鸡","Spicy Chicken","la zi ji",["重庆辣子鸡","辣子鸡丁"],"炒菜",300,[ing("鸡胸肉",220),ing("彩椒",40),ing("葱",20),ing("辣椒酱",20),ing("植物油",25)]),
 dish("宫保虾仁","Kung Pao Shrimp","gong bao xia ren",["宫爆虾仁"],"炒菜",320,[ing("虾仁",180),ing("彩椒",60),ing("洋葱",30),ing("生抽酱油",10),ing("白砂糖",5),ing("辣椒酱",10),ing("植物油",15)]),
 dish("清炒虾仁","Stir-Fried Shrimp","qing chao xia ren",["清炒虾","虾仁小炒"],"炒菜",280,[ing("虾仁",180),ing("黄瓜",80),ing("葱",10),ing("植物油",10)]),
 dish("韭菜炒鸡蛋","Chive Scrambled Eggs","jiu cai chao ji dan",["韭菜鸡蛋"],"炒菜",280,[ing("韭菜",150),ing("鸡蛋",120),ing("植物油",15)]),
 dish("菠菜炒鸡蛋","Spinach Scrambled Eggs","bo cai chao ji dan",["菠菜鸡蛋"],"炒菜",330,[ing("菠菜",200),ing("鸡蛋",120),ing("植物油",15)]),
 dish("蘑菇炒鸡蛋","Mushroom Scrambled Eggs","mo gu chao ji dan",["蘑菇鸡蛋","香菇炒蛋"],"炒菜",320,[ing("蘑菇",180),ing("鸡蛋",120),ing("植物油",15)]),
 dish("蒜蓉西兰花","Garlic Broccoli","suan rong xi lan hua",["蒜蓉绿花椰菜"],"炒菜",280,[ing("西兰花",250),ing("大蒜",15),ing("植物油",10)]),
 dish("清炒时蔬","Stir-Fried Seasonal Vegetables","qing chao shi shu",["清炒蔬菜","时蔬小炒"],"炒菜",300,[ing("卷心菜",250),ing("胡萝卜",30),ing("植物油",10)]),
 dish("手撕包菜","Hand-Torn Cabbage","shou si bao cai",["手撕圆白菜"],"炒菜",320,[ing("卷心菜",300),ing("辣椒酱",10),ing("大蒜",10),ing("植物油",15)]),
 dish("地三鲜","Di San Xian","di san xian",["东北地三鲜"],"炒菜",420,[ing("土豆",150),ing("茄子",150),ing("彩椒",100),ing("植物油",25),ing("生抽酱油",10),ing("白砂糖",5)]),
 dish("红烧茄子","Braised Eggplant","hong shao qie zi",["家常茄子"],"炒菜",350,[ing("茄子",300),ing("生抽酱油",15),ing("白砂糖",8),ing("大蒜",10),ing("植物油",20)]),
 dish("鱼香茄子","Yu Xiang Eggplant","yu xiang qie zi",["鱼香茄条"],"炒菜",380,[ing("茄子",300),ing("猪里脊",50),ing("辣椒酱",15),ing("生抽酱油",10),ing("米醋",8),ing("白砂糖",8),ing("植物油",20)]),
 dish("干煸四季豆","Dry-Fried Green Beans","gan bian si ji dou",["干煸豆角"],"炒菜",330,[ing("四季豆",250),ing("猪里脊",50),ing("辣椒酱",10),ing("植物油",20)]),
 dish("清炒豆芽","Stir-Fried Bean Sprouts","qing chao dou ya",["炒绿豆芽"],"炒菜",270,[ing("豆芽",250),ing("葱",10),ing("植物油",10)]),
 dish("醋溜土豆丝","Vinegar Potato Shreds","cu liu tu dou si",["酸辣土豆丝","醋溜马铃薯丝"],"炒菜",300,[ing("土豆",250),ing("米醋",10),ing("彩椒",30),ing("植物油",15)]),
 dish("酸辣土豆丝","Hot and Sour Potato Shreds","suan la tu dou si",["酸辣马铃薯丝"],"炒菜",300,[ing("土豆",250),ing("米醋",12),ing("辣椒酱",8),ing("植物油",15)]),
 dish("番茄炒菜花","Tomato Cauliflower","fan qie chao cai hua",["西红柿炒花菜"],"炒菜",400,[ing("花菜",250),ing("番茄",150),ing("植物油",15)]),
 dish("清炒莲藕","Stir-Fried Lotus Root","qing chao lian ou",["清炒藕片"],"炒菜",280,[ing("莲藕",250),ing("胡萝卜",30),ing("植物油",10)]),
 dish("蒜蓉菠菜","Garlic Spinach","suan rong bo cai",["蒜蓉菠菜叶"],"炒菜",260,[ing("菠菜",250),ing("大蒜",10),ing("植物油",10)]),
 dish("清炒生菜","Stir-Fried Lettuce","qing chao sheng cai",["蒜蓉生菜"],"炒菜",260,[ing("生菜",250),ing("大蒜",10),ing("植物油",10)]),
 dish("西葫芦炒蛋","Zucchini Scrambled Eggs","xi hu lu chao dan",["角瓜炒蛋"],"炒菜",320,[ing("西葫芦",200),ing("鸡蛋",120),ing("植物油",15)]),
 dish("苦瓜炒蛋","Bitter Melon Scrambled Eggs","ku gua chao dan",["凉瓜炒蛋"],"炒菜",320,[ing("苦瓜",200),ing("鸡蛋",120),ing("植物油",15)]),
 dish("南瓜炒肉","Pumpkin Pork Stir-Fry","nan gua chao rou",["南瓜炒猪肉"],"炒菜",350,[ing("猪里脊",100),ing("南瓜",250),ing("生抽酱油",10),ing("植物油",15)]),
 dish("山药炒木耳","Yam with Wood Ear Mushroom","shan yao chao mu er",["山药蘑菇","山药木耳"],"炒菜",340,[ing("山药",250),ing("蘑菇",80),ing("植物油",10)]),
 dish("冬瓜虾仁","Winter Melon with Shrimp","dong gua xia ren",["冬瓜炒虾仁"],"炒菜",350,[ing("冬瓜",250),ing("虾仁",120),ing("葱",10),ing("植物油",10)]),
 dish("秋葵炒虾仁","Okra Shrimp Stir-Fry","qiu kui chao xia ren",["秋葵虾仁"],"炒菜",350,[ing("秋葵",200),ing("虾仁",150),ing("植物油",10)]),
 dish("芦笋炒虾仁","Asparagus Shrimp Stir-Fry","lu sun chao xia ren",["芦笋虾仁"],"炒菜",350,[ing("芦笋",200),ing("虾仁",150),ing("植物油",10)]),
 dish("韭菜炒虾仁","Chive Shrimp Stir-Fry","jiu cai chao xia ren",["韭菜虾仁"],"炒菜",300,[ing("韭菜",150),ing("虾仁",150),ing("植物油",10)]),
 dish("彩椒鸡丁","Bell Pepper Chicken","cai jiao ji ding",["彩椒鸡肉丁"],"炒菜",380,[ing("鸡胸肉",180),ing("彩椒",150),ing("洋葱",50),ing("生抽酱油",10),ing("植物油",15)]),
 dish("青椒土豆丝","Green Pepper Potato Shreds","qing jiao tu dou si",["尖椒土豆丝"],"炒菜",300,[ing("土豆",250),ing("彩椒",50),ing("植物油",12)]),
 dish("番茄炖牛腩","Tomato Beef Brisket","fan qie dun niu nan",["西红柿炖牛肉","番茄牛腩"],"炖煮",420,[ing("牛里脊",220),ing("番茄",220),ing("洋葱",50),ing("植物油",10)]),
 dish("土豆炖牛肉","Potato Beef Stew","tu dou dun niu rou",["牛肉炖土豆"],"炖煮",450,[ing("牛里脊",220),ing("土豆",220),ing("胡萝卜",80),ing("生抽酱油",15)]),
 dish("香菇炖鸡","Braised Chicken with Mushrooms","xiang gu dun ji",["香菇鸡","炖鸡"],"炖煮",450,[ing("鸡胸肉",250),ing("蘑菇",150),ing("生姜",8),ing("生抽酱油",15)]),
 dish("红烧鸡腿","Red-Braised Chicken","hong shao ji tui",["红烧鸡块"],"炖煮",400,[ing("鸡胸肉",300),ing("生抽酱油",20),ing("白砂糖",8),ing("生姜",8)]),
 dish("白菜炖豆腐","Cabbage Tofu Stew","bai cai dun dou fu",["白菜豆腐"],"炖煮",450,[ing("大白菜",250),ing("北豆腐",200),ing("植物油",10)]),
]
# 11 additional braises to reach 15
D += [
 dish("冬瓜炖肉","Winter Melon Pork Stew","dong gua dun rou",["冬瓜猪肉"],"炖煮",420,[ing("冬瓜",250),ing("猪里脊",170),ing("生抽酱油",10)]),
 dish("玉米炖鸡","Corn Chicken Stew","yu mi dun ji",["玉米鸡"],"炖煮",450,[ing("鸡胸肉",250),ing("玉米",200),ing("胡萝卜",60)]),
 dish("红烧鳕鱼","Braised Cod","hong shao xue yu",["红烧鱼"],"炖煮",330,[ing("鳕鱼",250),ing("生抽酱油",15),ing("生姜",8),ing("植物油",10)]),
 dish("清蒸鳕鱼","Steamed Cod","qing zheng xue yu",["清蒸鱼"],"炖煮",300,[ing("鳕鱼",280),ing("葱",10),ing("生姜",8),ing("芝麻油",5)]),
]
# 15 staples
D += [
 dish("蛋炒饭","Egg Fried Rice","dan chao fan",["鸡蛋炒饭"],"主食",350,[ing("白米饭",250),ing("鸡蛋",100),ing("葱",10),ing("植物油",12)]),
 dish("扬州炒饭","Yangzhou Fried Rice","yang zhou chao fan",["什锦炒饭"],"主食",380,[ing("白米饭",250),ing("鸡蛋",80),ing("虾仁",60),ing("胡萝卜",40),ing("植物油",12)]),
 dish("牛肉炒饭","Beef Fried Rice","niu rou chao fan",["牛肉米饭"],"主食",400,[ing("白米饭",250),ing("牛里脊",100),ing("胡萝卜",40),ing("植物油",12)]),
 dish("番茄鸡蛋面","Tomato Egg Noodles","fan qie ji dan mian",["西红柿鸡蛋面"],"主食",450,[ing("熟面条",250),ing("番茄",150),ing("鸡蛋",100)]),
 dish("牛肉面","Beef Noodles","niu rou mian",["红烧牛肉面"],"主食",500,[ing("熟面条",250),ing("牛里脊",120),ing("大白菜",100),ing("生抽酱油",10)]),
 dish("炸酱面","Zhajiang Noodles","zha jiang mian",["炸酱面条"],"主食",420,[ing("熟面条",250),ing("猪里脊",100),ing("黄瓜",50),ing("生抽酱油",20)]),
 dish("阳春面","Plain Noodles","yang chun mian",["清汤面"],"主食",360,[ing("熟面条",250),ing("葱",10),ing("生抽酱油",8),ing("芝麻油",5)]),
 dish("炒面","Stir-Fried Noodles","chao mian",["家常炒面"],"主食",380,[ing("熟面条",250),ing("卷心菜",100),ing("胡萝卜",40),ing("植物油",12)]),
 dish("猪肉白菜水饺","Pork Cabbage Dumplings","zhu rou bai cai shui jiao",["白菜猪肉饺子","水饺"],"主食",300,[ing("水饺",300)]),
 dish("鸡蛋水饺","Egg Dumplings","ji dan shui jiao",["鸡蛋饺子"],"主食",280,[ing("水饺",260),ing("鸡蛋",60)]),
 dish("煎饺","Pan-Fried Dumplings","jian jiao",["锅贴"],"主食",280,[ing("水饺",260),ing("植物油",10)]),
 dish("牛肉饺子","Beef Dumplings","niu rou jiao zi",["牛肉水饺"],"主食",300,[ing("水饺",280),ing("牛里脊",80)]),
 dish("蔬菜炒面","Vegetable Noodles","shu cai chao mian",["素炒面"],"主食",380,[ing("熟面条",250),ing("卷心菜",100),ing("彩椒",50),ing("植物油",10)]),
 dish("鸡丝面","Chicken Noodle Soup","ji si mian",["鸡肉面"],"主食",450,[ing("熟面条",250),ing("鸡胸肉",100),ing("菠菜",80)]),
 dish("番茄牛肉面","Tomato Beef Noodles","fan qie niu rou mian",["西红柿牛肉面"],"主食",500,[ing("熟面条",250),ing("牛里脊",120),ing("番茄",150)]),
]
# 10 soups
D += [
 dish("紫菜蛋花汤","Seaweed Egg Drop Soup","zi cai dan hua tang",["海带蛋花汤"],"汤羹",350,[ing("海带",30),ing("鸡蛋",60),ing("芝麻油",3)]),
 dish("番茄蛋汤","Tomato Egg Soup","fan qie dan tang",["西红柿鸡蛋汤"],"汤羹",400,[ing("番茄",180),ing("鸡蛋",60),ing("芝麻油",3)]),
 dish("冬瓜汤","Winter Melon Soup","dong gua tang",["清汤冬瓜"],"汤羹",400,[ing("冬瓜",300),ing("葱",8),ing("芝麻油",3)]),
 dish("玉米排骨汤","Corn Pork Soup","yu mi pai gu tang",["玉米猪肉汤"],"汤羹",500,[ing("玉米",200),ing("猪里脊",180),ing("胡萝卜",60)]),
 dish("蔬菜汤","Vegetable Soup","shu cai tang",["什锦蔬菜汤"],"汤羹",450,[ing("卷心菜",120),ing("胡萝卜",80),ing("番茄",120),ing("洋葱",50)]),
 dish("豆腐汤","Tofu Soup","dou fu tang",["清汤豆腐"],"汤羹",400,[ing("北豆腐",250),ing("菠菜",100),ing("葱",8)]),
 dish("蘑菇汤","Mushroom Soup","mo gu tang",["香菇汤"],"汤羹",400,[ing("蘑菇",250),ing("全脂牛奶",100),ing("洋葱",50)]),
 dish("海带汤","Kelp Soup","hai dai tang",["昆布汤"],"汤羹",400,[ing("海带",150),ing("北豆腐",150),ing("葱",8)]),
 dish("南瓜汤","Pumpkin Soup","nan gua tang",["奶油南瓜汤"],"汤羹",400,[ing("南瓜",300),ing("全脂牛奶",100)]),
 dish("豌豆汤","Pea Soup","wan dou tang",["青豆汤"],"汤羹",400,[ing("豌豆",250),ing("洋葱",50),ing("植物油",5)]),
]
# 10 breakfasts
D += [
 dish("鸡蛋三明治","Egg Sandwich","ji dan san ming zhi",["鸡蛋吐司三明治"],"早餐",180,[ing("白面包",80),ing("鸡蛋",80),ing("生菜",20)]),
 dish("牛奶燕麦","Milk Oatmeal","niu nai yan mai",["燕麦牛奶","牛奶麦片"],"早餐",350,[ing("燕麦片",60),ing("全脂牛奶",280)]),
 dish("香蕉燕麦","Banana Oatmeal","xiang jiao yan mai",["香蕉麦片"],"早餐",350,[ing("燕麦片",60),ing("香蕉",120),ing("全脂牛奶",180)]),
 dish("蔬菜蛋饼","Vegetable Egg Pancake","shu cai dan bing",["鸡蛋蔬菜饼"],"早餐",250,[ing("鸡蛋",100),ing("卷心菜",80),ing("胡萝卜",40),ing("植物油",8)]),
 dish("豆浆面包","Soy Milk with Bread","dou jiang mian bao",["豆浆吐司"],"早餐",350,[ing("无糖豆浆",250),ing("白面包",80)]),
 dish("酸奶水果杯","Yogurt Fruit Bowl","suan nai shui guo bei",["水果酸奶"],"早餐",350,[ing("无糖希腊酸奶",200),ing("草莓",80),ing("蓝莓",60)]),
 dish("牛奶香蕉杯","Milk Banana Bowl","niu nai xiang jiao bei",["香蕉牛奶"],"早餐",400,[ing("全脂牛奶",280),ing("香蕉",120)]),
 dish("花生酱吐司","Peanut Butter Toast","hua sheng jiang tu si",["花生酱面包"],"早餐",120,[ing("白面包",80),ing("花生酱",30)]),
 dish("水果燕麦杯","Fruit Oatmeal Bowl","shui guo yan mai bei",["燕麦水果"],"早餐",380,[ing("燕麦片",60),ing("无糖希腊酸奶",180),ing("蓝莓",60),ing("草莓",60)]),
 dish("鸡蛋牛奶早餐","Egg and Milk Breakfast","ji dan niu nai zao can",["鸡蛋牛奶"],"早餐",350,[ing("鸡蛋",100),ing("全脂牛奶",240),ing("白面包",60)]),
]
# 10 cold dishes
D += [
 dish("凉拌黄瓜","Cucumber Salad","liang ban huang gua",["拍黄瓜"],"凉菜",250,[ing("黄瓜",220),ing("大蒜",8),ing("米醋",10),ing("芝麻油",5)]),
 dish("凉拌木耳","Wood Ear Mushroom Salad","liang ban mu er",["凉拌蘑菇"],"凉菜",250,[ing("蘑菇",200),ing("米醋",10),ing("芝麻油",5),ing("大蒜",8)]),
 dish("凉拌海带丝","Kelp Salad","liang ban hai dai si",["海带丝"],"凉菜",250,[ing("海带",220),ing("米醋",10),ing("芝麻油",5),ing("大蒜",8)]),
 dish("凉拌菠菜","Spinach Salad","liang ban bo cai",["菠菜凉菜"],"凉菜",250,[ing("菠菜",220),ing("芝麻油",5),ing("大蒜",8)]),
 dish("凉拌豆腐","Tofu Salad","liang ban dou fu",["小葱拌豆腐"],"凉菜",280,[ing("北豆腐",250),ing("葱",12),ing("芝麻油",5)]),
 dish("凉拌豆芽","Bean Sprout Salad","liang ban dou ya",["豆芽凉菜"],"凉菜",250,[ing("豆芽",220),ing("米醋",8),ing("芝麻油",5)]),
 dish("凉拌鸡丝","Chicken Salad","liang ban ji si",["鸡丝凉菜"],"凉菜",300,[ing("鸡胸肉",180),ing("黄瓜",80),ing("米醋",8),ing("芝麻油",5)]),
 dish("凉拌牛肉","Beef Salad","liang ban niu rou",["牛肉凉菜"],"凉菜",300,[ing("牛里脊",180),ing("黄瓜",80),ing("生抽酱油",8),ing("芝麻油",5)]),
 dish("凉拌藕片","Lotus Root Salad","liang ban ou pian",["藕片凉菜"],"凉菜",280,[ing("莲藕",250),ing("米醋",10),ing("芝麻油",5)]),
 dish("凉拌西兰花","Broccoli Salad","liang ban xi lan hua",["西兰花凉菜"],"凉菜",280,[ing("西兰花",250),ing("芝麻油",5),ing("大蒜",8)]),
]
# 10 coffee / milk tea
D += [
 dish("冰拿铁","Iced Latte","bing na tie",["冰拿铁咖啡"],"咖啡奶茶",350,[ing("浓缩咖啡",60),ing("全脂牛奶",240),ing("白砂糖",8)],portion="1杯",aliases_en=["iced latte"]),
 dish("焦糖拿铁","Caramel Latte","jiao tang na tie",["焦糖拿铁咖啡"],"咖啡奶茶",350,[ing("浓缩咖啡",60),ing("全脂牛奶",240),ing("白砂糖",18)],portion="1杯",aliases_en=["caramel latte"]),
 dish("香草拿铁","Vanilla Latte","xiang cao na tie",["香草拿铁咖啡"],"咖啡奶茶",350,[ing("浓缩咖啡",60),ing("全脂牛奶",240),ing("白砂糖",12)],portion="1杯",aliases_en=["vanilla latte"]),
 dish("燕麦拿铁","Oat Milk Latte","yan mai na tie",["燕麦奶拿铁"],"咖啡奶茶",350,[ing("浓缩咖啡",60),ing("燕麦片",40),ing("全脂牛奶",180)],portion="1杯",aliases_en=["oat latte"]),
 dish("摩卡咖啡饮品","Cafe Mocha","mo ka ka fei",["摩卡咖啡","摩卡"],"咖啡奶茶",350,[ing("浓缩咖啡",60),ing("全脂牛奶",220),ing("白砂糖",15),ing("牛奶巧克力",20)],portion="1杯",aliases_en=["mocha"]),
 dish("卡布奇诺饮品","Cappuccino","ka bu qi nuo",["卡布奇诺咖啡"],"咖啡奶茶",300,[ing("浓缩咖啡",60),ing("全脂牛奶",220)],portion="1杯",aliases_en=["cappuccino"]),
 dish("珍珠奶茶","Bubble Milk Tea","zhen zhu nai cha",["珍珠奶盖茶","奶茶"],"咖啡奶茶",500,[ing("全脂牛奶",250),ing("白砂糖",25),ing("水饺",50)],portion="1杯",aliases_en=["bubble tea"]),
 dish("巧克力奶饮","Chocolate Milk Drink","qiao ke li nai",["巧克力牛奶"],"咖啡奶茶",400,[ing("全脂牛奶",300),ing("牛奶巧克力",50)],portion="1杯",aliases_en=["chocolate milk"]),
 dish("香蕉牛奶饮品","Banana Milk","xiang jiao niu nai",["香蕉奶昔"],"咖啡奶茶",450,[ing("全脂牛奶",300),ing("香蕉",150)],portion="1杯",aliases_en=["banana milk"]),
 dish("草莓酸奶饮品","Strawberry Yogurt Drink","cao mei suan nai",["草莓酸奶昔"],"咖啡奶茶",400,[ing("无糖希腊酸奶",220),ing("草莓",150),ing("全脂牛奶",80)],portion="1杯",aliases_en=["strawberry yogurt drink"]),
]
# 10 desserts / packaged snacks
D += [
 dish("水果酸奶碗","Fruit Yogurt Bowl","shui guo suan nai wan",["酸奶水果碗"],"甜品",350,[ing("无糖希腊酸奶",200),ing("香蕉",80),ing("草莓",60)]),
 dish("芒果奶昔","Mango Milkshake","mang guo nai xi",["芒果牛奶"],"甜品",400,[ing("芒果",180),ing("全脂牛奶",220)]),
 dish("蓝莓酸奶杯","Blueberry Yogurt Cup","lan mei suan nai bei",["蓝莓酸奶"],"甜品",300,[ing("无糖希腊酸奶",220),ing("蓝莓",80)]),
 dish("香蕉花生酱吐司","Banana Peanut Butter Toast","xiang jiao hua sheng jiang tu si",["香蕉吐司"],"甜品",180,[ing("白面包",80),ing("花生酱",30),ing("香蕉",80)]),
 dish("巧克力香蕉杯","Chocolate Banana Bowl","qiao ke li xiang jiao bei",["巧克力香蕉"],"甜品",300,[ing("香蕉",180),ing("牛奶巧克力",50),ing("无糖希腊酸奶",120)]),
 dish("草莓冰淇淋杯","Strawberry Ice Cream Cup","cao mei bing qi lin bei",["草莓冰淇淋"],"甜品",250,[ing("香草冰淇淋",180),ing("草莓",80)]),
 dish("巧克力冰淇淋杯","Chocolate Ice Cream Cup","qiao ke li bing qi lin bei",["巧克力冰淇淋"],"甜品",250,[ing("香草冰淇淋",180),ing("牛奶巧克力",50)]),
 dish("水果坚果酸奶","Fruit Nut Yogurt","shui guo jian guo suan nai",["坚果酸奶"],"甜品",320,[ing("无糖希腊酸奶",200),ing("苹果",80),ing("杏仁",25)]),
 dish("燕麦能量杯","Oat Energy Cup","yan mai neng liang bei",["燕麦杯"],"甜品",300,[ing("燕麦片",60),ing("花生酱",25),ing("香蕉",100)]),
 dish("巧克力牛奶燕麦","Chocolate Milk Oatmeal","qiao ke li niu nai yan mai",["巧克力燕麦"],"甜品",350,[ing("燕麦片",60),ing("巧克力奶",250)]),
]
if len(D) != 120:
    raise SystemExit(f"expected 120 dishes, got {len(D)}")
ids = [item["id"] for item in D]
if len(ids) != len(set(ids)):
    raise SystemExit("duplicate dish IDs")
OUTPUT.parent.mkdir(parents=True, exist_ok=True)
OUTPUT.write_text(json.dumps({
    "schemaVersion": 1,
    "catalogVersion": "2026-10-19-v1",
    "dishes": D,
}, ensure_ascii=False, indent=2) + "\n")
print(f"wrote {len(D)} dishes to {OUTPUT}")
