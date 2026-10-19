#!/usr/bin/env python3
import argparse, hashlib, json, re, sqlite3, subprocess, uuid, zipfile, tempfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SEED = ROOT / 'Packages/NutritionKit/Sources/NutritionKit/Resources/SeedFoods.json'
DEFAULT_OVERLAY = ROOT / 'Packages/NutritionKit/Sources/NutritionKit/Resources/FoodLocalizationOverlay.json'
DEFAULT_TRANSLATIONS = ROOT / 'CatalogData/FoodNameZhTranslations.json'
DEFAULT_PREPARED = ROOT / 'CatalogData/ChinesePreparedDishOverlay.json'

USDA_UNITS = {
    'energy_kcal':'kcal','protein_g':'g','fat_g':'g','carbohydrate_g':'g','fiber_g':'g','sugar_g':'g','sodium_mg':'mg',
    'saturated_fat_g':'g','monounsaturated_fat_g':'g','polyunsaturated_fat_g':'g','trans_fat_g':'g','cholesterol_mg':'mg',
    'potassium_mg':'mg','calcium_mg':'mg','iron_mg':'mg','magnesium_mg':'mg','phosphorus_mg':'mg','zinc_mg':'mg','selenium_ug':'ug',
    'vitamin_a_ug':'ug','vitamin_c_mg':'mg','vitamin_d_ug':'ug','vitamin_e_mg':'mg','vitamin_k_ug':'ug','thiamin_mg':'mg',
    'riboflavin_mg':'mg','niacin_mg':'mg','vitamin_b6_mg':'mg','folate_ug':'ug','vitamin_b12_ug':'ug','caffeine_mg':'mg'
}
USDA_NUMBER_MAP = {
    '203':'protein_g','204':'fat_g','205':'carbohydrate_g','291':'fiber_g','269':'sugar_g','307':'sodium_mg',
    '606':'saturated_fat_g','645':'monounsaturated_fat_g','646':'polyunsaturated_fat_g','605':'trans_fat_g','601':'cholesterol_mg',
    '306':'potassium_mg','301':'calcium_mg','303':'iron_mg','304':'magnesium_mg','305':'phosphorus_mg','309':'zinc_mg','317':'selenium_ug',
    '320':'vitamin_a_ug','401':'vitamin_c_mg','328':'vitamin_d_ug','323':'vitamin_e_mg','430':'vitamin_k_ug','404':'thiamin_mg',
    '405':'riboflavin_mg','406':'niacin_mg','415':'vitamin_b6_mg','417':'folate_ug','418':'vitamin_b12_ug','1057':'caffeine_mg'
}
TW_NUTRIENT_MAP = {
    '熱量':'energy_kcal','蛋白質':'protein_g','粗蛋白':'protein_g','脂肪':'fat_g','粗脂肪':'fat_g','碳水化合物':'carbohydrate_g',
    '膳食纖維':'fiber_g','纖維':'fiber_g','糖':'sugar_g','糖質':'sugar_g','鈉':'sodium_mg','飽和脂肪':'saturated_fat_g',
    '單元不飽和脂肪':'monounsaturated_fat_g','多元不飽和脂肪':'polyunsaturated_fat_g','反式脂肪':'trans_fat_g','膽固醇':'cholesterol_mg',
    '鉀':'potassium_mg','鈣':'calcium_mg','鐵':'iron_mg','鎂':'magnesium_mg','磷':'phosphorus_mg','鋅':'zinc_mg','硒':'selenium_ug',
    '維生素A':'vitamin_a_ug','維生素C':'vitamin_c_mg','維生素D':'vitamin_d_ug','維生素E':'vitamin_e_mg','維生素K':'vitamin_k_ug',
    '維生素B1':'thiamin_mg','維生素B2':'riboflavin_mg','菸鹼素':'niacin_mg','維生素B6':'vitamin_b6_mg','葉酸':'folate_ug','維生素B12':'vitamin_b12_ug','咖啡因':'caffeine_mg'
}

def now_iso(): return datetime.now(timezone.utc).isoformat().replace('+00:00','Z')
def stable_uuid(namespace, value): return str(uuid.uuid5(uuid.NAMESPACE_URL, f'nutritiondiary:{namespace}:{value}'))
def normalize_name(value): return re.sub(r'[\s\W_]+','',value.lower(),flags=re.UNICODE)
def convert_unit(value, source, target):
    if value is None: return None
    if source == target: return value
    if source == 'kcal' and target == 'kcal': return value
    if source == 'g' and target == 'mg': return value * 1000
    if source == 'mg' and target == 'g': return value / 1000
    if source == 'mg' and target == 'ug': return value * 1000
    if source == 'ug' and target == 'mg': return value / 1000
    if source == 'g' and target == 'ug': return value * 1_000_000
    if source == 'ug' and target == 'g': return value / 1_000_000
    return None

def search_terms(names):
    result = set()
    for name in names:
        if not name: continue
        name = name.strip()
        result.add(name)
        for word in re.findall(r'[A-Za-z0-9]+', name): result.add(word.lower())
        cjk = ''.join(re.findall(r'[\u3400-\u9fff]', name))
        result.update(cjk)
        result.update(cjk[i:i+2] for i in range(max(0,len(cjk)-1)))
    return ' '.join(sorted(result))

def nutrient(code, value, source='importedCatalog', status='complete'):
    return {'nutrient': code, 'value': value, 'unit': USDA_UNITS.get(code,'g'), 'status': status, 'source': source}

def make_food(uid,name,category,nutrients,source,portions=None,aliases=None,edible=1.0,name_zh=None,name_en=None,name_zh_origin=None,category_zh=None,category_en=None):
    aliases = aliases or []
    return {
        'id':uid,'name':name,'nameZh':name_zh,'nameEn':name_en,'nameZhOrigin':name_zh_origin,'aliases':aliases,'category':category or '其他食品',
        'categoryZh':category_zh or category or '其他食品','categoryEn':category_en or category or 'Other foods',
        'referenceAmount':100,'referenceUnit':'g','edibleRatio':edible,'densityGramsPerMilliliter':None,
        'nutrients':nutrients,'portions':portions or [],'source':source,'barcode':None,'isFavorite':False
    }

USDA_CATEGORY_ZH = {
    'Baked Products':'烘焙食品','Beef Products':'牛肉制品','Beverages':'饮料','Breakfast Cereals':'早餐谷物',
    'Cereal Grains and Pasta':'谷物与面食','Dairy and Egg Products':'乳制品与蛋类','Fats and Oils':'油脂',
    'Finfish and Shellfish Products':'鱼类与贝类','Fruits and Fruit Juices':'水果与果汁','Legumes and Legume Products':'豆类制品',
    'Nut and Seed Products':'坚果与种子','Pork Products':'猪肉制品','Poultry Products':'禽肉制品','Restaurant Foods':'餐厅食品',
    'Sausages and Luncheon Meats':'香肠与冷切肉','Soups, Sauces, and Gravies':'汤、酱汁与肉汁','Snacks':'零食',
    'Sweets':'甜食','Vegetables and Vegetable Products':'蔬菜与蔬菜制品','Fast Foods':'快餐','Coffee':'咖啡','Tea':'茶',
    'Rice':'米饭','Pasta, noodles, cooked grains':'面食、面条与熟谷物','Eggs and omelets':'鸡蛋与煎蛋','Cheese':'奶酪',
    'Milk, whole':'全脂牛奶','Milk, lowfat':'低脂牛奶','Milk, nonfat':'脱脂牛奶','Yogurt, Greek':'希腊酸奶',
    'Yogurt, regular':'普通酸奶','Ice cream and frozen dairy desserts':'冰淇淋与冷冻乳品甜点','Fruit drinks':'水果饮料',
    'Vegetable juice':'蔬菜汁','Citrus fruits':'柑橘类水果','Citrus juice':'柑橘汁','Apples':'苹果','Bananas':'香蕉',
    'Grapes':'葡萄','Strawberries':'草莓','Blueberries and other berries':'蓝莓与浆果','Mango and papaya':'芒果与木瓜',
    'Melons':'瓜类','Peaches and nectarines':'桃与油桃','Pears':'梨','Pineapple':'菠萝','Dried fruits':'水果干',
    'Tomatoes':'番茄','Carrots':'胡萝卜','Broccoli':'西兰花','Spinach':'菠菜','Cabbage':'卷心菜','Corn':'玉米',
    'Onions':'洋葱','Lettuce and lettuce salads':'生菜与沙拉','Other vegetables and combinations':'其他蔬菜及组合',
    'Potato chips':'薯片','French fries and other fried white potatoes':'炸薯条与炸土豆','Rice mixed dishes':'米饭混合菜',
    'Pizza':'披萨','Burgers':'汉堡','Burritos and tacos':'墨西哥卷饼与塔可','Nachos':'玉米片',
    'Pasta mixed dishes, excludes macaroni and cheese':'意面混合菜','Macaroni and cheese':'芝士通心粉',
    'Soy and meat-alternative products':'大豆与肉类替代品','Plant-based milk':'植物奶','Plant-based yogurt':'植物酸奶',
    'Nutrition bars':'营养棒','Cereal bars':'谷物棒','Candy containing chocolate':'含巧克力糖果','Candy not containing chocolate':'不含巧克力糖果'
}

def usda_category_zh(category):
    return USDA_CATEGORY_ZH.get(category, '其他食品')

def read_json_path(path):
    path=Path(path)
    if path.suffix.lower()=='.zip':
        with zipfile.ZipFile(path) as z:
            return json.loads(z.read(z.namelist()[0]).decode('utf-8-sig'))
    with open(path,encoding='utf-8-sig') as f:
        return json.load(f)

def load_usda(path, kind, label):
    data=read_json_path(path)
    key = 'FoundationFoods' if kind=='foundation' else 'SRLegacyFoods' if kind=='sr' else 'SurveyFoods'
    foods=[]
    for item in data.get(key,[]):
        if not isinstance(item,dict): continue
        name=(item.get('description') or '').strip()
        if not name: continue
        nutrients_by_code={}
        for fn in item.get('foodNutrients',[]):
            n=fn.get('nutrient') or {}; number=str(n.get('number','')); amount=fn.get('amount')
            code=USDA_NUMBER_MAP.get(number)
            if not code or amount is None: continue
            target=USDA_UNITS[code]; converted=convert_unit(float(amount),n.get('unitName','g'),target)
            if converted is None: continue
            if code in nutrients_by_code and code=='energy_kcal': continue
            nutrients_by_code[code]=converted
        for energy_number in ['208','957','958']:
            if 'energy_kcal' in nutrients_by_code: break
            for fn in item.get('foodNutrients',[]):
                n=fn.get('nutrient') or {}
                if str(n.get('number',''))==energy_number and fn.get('amount') is not None:
                    nutrients_by_code['energy_kcal']=float(fn['amount']); break
        if not nutrients_by_code: continue
        portions=[]
        for portion in item.get('foodPortions',[]):
            grams=portion.get('gramWeight')
            if not grams or grams<=0: continue
            portion_label=portion.get('portionDescription') or portion.get('modifier') or '1份'
            portions.append({'id':stable_uuid('portion',f"{kind}:{item.get('fdcId')}:{portion.get('id')}"),'label':str(portion_label),'amount':float(grams),'unit':'g','approximate':True})
        category=(item.get('foodCategory') or {}).get('description') or (item.get('wweiaFoodCategory') or {}).get('wweiaFoodCategoryDescription') or 'USDA'
        source={'kind':'imported','identifier':f"{kind}:{item.get('fdcId')}",'title':label,'license':'Public Domain','sourceURL':'https://fdc.nal.usda.gov/','retrievedAt':now_iso()}
        foods.append(make_food(stable_uuid('usda',f"{kind}:{item.get('fdcId')}"),name,category,[nutrient(k,v) for k,v in sorted(nutrients_by_code.items())],source,portions,name_zh=None,name_en=name,category_zh=usda_category_zh(category),category_en=category))
    return foods

def load_seed(path, overlay_path=DEFAULT_OVERLAY):
    data=json.load(open(path,encoding='utf-8'))
    overlay=json.load(open(overlay_path,encoding='utf-8'))
    overlay_foods={item['id']:item for item in overlay.get('foods',[])}
    categories=overlay.get('categories',{})
    portion_labels=overlay.get('portionLabels',{})
    source_titles=overlay.get('sourceTitles',{})
    foods=[]
    for item in data['foods']:
        ns=[]
        for code,value in item['nutrients'].items():
            ns.append(nutrient(code,float(value),source='bundledCatalog',status='estimated' if code in item.get('estimatedNutrients',[]) else 'complete'))
        source_title=item['source'].get('title','Seed')
        source={'kind':'bundled','identifier':item['source'].get('identifier'),'title':source_title,'titleZh':source_title,'titleEn':source_titles.get(source_title,source_title),'license':item['source'].get('license'),'sourceURL':item['source'].get('url'),'retrievedAt':item['source'].get('retrievedAt')}
        portions=[]
        for index, portion in enumerate(item.get('portions',[])):
            p=dict(portion)
            p.setdefault('id',stable_uuid('portion',f"seed:{item['uuid']}:{index}"))
            p.setdefault('approximate',True)
            p['labelZh']=portion.get('label')
            p['labelEn']=portion_labels.get(portion.get('label'),portion.get('label'))
            portions.append(p)
        localized=overlay_foods.get(item['uuid'],{})
        foods.append(make_food(item['uuid'],item['name'],item['category'],ns,source,portions,item.get('aliases',[]),float(item.get('edibleRatio',1)),name_zh=localized.get('nameZh',item['name']),name_en=localized.get('nameEn'),name_zh_origin='curated',category_zh=localized.get('categoryZh',item['category']),category_en=localized.get('categoryEn',categories.get(item['category']))))
    return foods

def load_prepared_overlay(path, seed_foods):
    data=json.load(open(path,encoding='utf-8'))
    if data.get('schemaVersion') != 1:
        raise ValueError('unsupported prepared-dish overlay schema')
    seed_by_id={food['id']:food for food in seed_foods}
    foods=[]
    for item in data.get('dishes',[]):
        yield_grams=float(item.get('finalYieldGrams') or 0)
        if yield_grams <= 0:
            raise ValueError(f"invalid yield for {item.get('nameZh')}")
        totals={}; units={}; missing=set(); estimated=set()
        for ingredient in item.get('ingredients',[]):
            food=seed_by_id.get(ingredient.get('foodUUID'))
            if food is None:
                raise ValueError(f"missing ingredient UUID for {item.get('nameZh')}: {ingredient.get('foodUUID')}")
            amount=float(ingredient.get('amount') or 0); unit=ingredient.get('unit','g')
            reference=float(food.get('referenceAmount',100))
            factor=None
            if unit==food.get('referenceUnit'):
                factor=amount/reference
            elif unit=='g' and food.get('referenceUnit')=='ml' and food.get('densityGramsPerMilliliter'):
                factor=(amount/float(food['densityGramsPerMilliliter']))/reference
            elif unit=='ml' and food.get('referenceUnit')=='g' and food.get('densityGramsPerMilliliter'):
                factor=(amount*float(food['densityGramsPerMilliliter']))/reference
            if factor is None:
                raise ValueError(f"incompatible ingredient unit for {item.get('nameZh')}: {food.get('name')}")
            present=set()
            for measurement in food.get('nutrients',[]):
                code=measurement['nutrient']; units[code]=measurement.get('unit'); present.add(code)
                if measurement.get('value') is None or measurement.get('status')=='missing':
                    missing.add(code)
                else:
                    totals[code]=totals.get(code,0)+float(measurement['value'])*factor
                    if measurement.get('status')=='estimated': estimated.add(code)
            for code in USDA_UNITS:
                if code not in present: missing.add(code)
        yield_factor=100/yield_grams
        nutrients=[]
        for code in USDA_UNITS:
            if code not in totals and code not in missing:
                continue
            status='missing' if code in missing else ('estimated' if code in estimated else 'complete')
            nutrients.append({
                'nutrient':code,
                'value':None if status=='missing' else totals.get(code,0)*yield_factor,
                'unit':USDA_UNITS[code],
                'status':status,
                'source':'recipe' if status!='missing' else 'importedCatalog',
            })
        source={'kind':'bundled','identifier':f"prepared:{item['id']}",'title':item['source'].get('title','NutritionDiary Chinese prepared dish recipe'),'titleZh':'NutritionDiary 中式复合菜配方','titleEn':'NutritionDiary Chinese prepared dish recipe','license':item['source'].get('license','Curated internal recipe based on licensed ingredient data'),'sourceURL':item['source'].get('url'),'retrievedAt':item['source'].get('retrievedAt')}
        portions=[]
        for index, portion in enumerate(item.get('servings',[])):
            portions.append({'id':stable_uuid('prepared-portion',f"{item['id']}:{index}"),'label':portion.get('label','1份'),'labelZh':portion.get('label','1份'),'labelEn':'1 serving','amount':float(portion.get('amount',yield_grams)),'unit':portion.get('unit','g'),'approximate':bool(portion.get('approximate',True))})
        food=make_food(item['id'],item['nameZh'],item['categoryEn'],[],source,portions,item.get('aliasesZh',[]),1.0,name_zh=item['nameZh'],name_en=item.get('nameEn'),name_zh_origin='curated',category_zh=item.get('categoryZh'),category_en=item.get('categoryEn'))
        food['nutrients']=nutrients
        food['aliases']=list(dict.fromkeys(item.get('aliasesZh',[])+item.get('aliasesEn',[])))
        food['pinyin']=item.get('pinyin',[])
        food['canonicalGroupID']=f"prepared:{normalize_name(item['nameZh'])}"
        food['preparationState']='prepared'
        food['dataQuality']='curated'
        food['searchPriority']=100
        food['commonality']=0.9
        foods.append(food)
    return foods

def simplify_names(values):
    if not values: return {}
    script=ROOT/'Scripts/traditional_to_simplified.swift'
    try:
        proc=subprocess.run(['swift',str(script)],input=json.dumps(values,ensure_ascii=False).encode(),stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,check=True)
        converted=json.loads(proc.stdout)
        return dict(zip(values,converted))
    except Exception:
        return {v:v for v in values}

def load_taiwan(path):
    raw=Path(path)
    if raw.suffix.lower()=='.zip':
        with zipfile.ZipFile(raw) as z:
            txt=z.read(z.namelist()[0]).decode('utf-8-sig')
    else: txt=raw.read_text(encoding='utf-8-sig')
    data=json.loads(txt)
    rows=data if isinstance(data,list) else data.get('data') or data.get('records') or []
    groups={}
    for row in rows:
        if not isinstance(row,dict): continue
        key=str(row.get('整合編號') or row.get('樣品名稱') or '')
        if not key: continue
        groups.setdefault(key,[]).append(row)
    names=[]
    for group in groups.values():
        r=group[0]
        names += [str(r.get('樣品名稱','')),str(r.get('俗名','')),str(r.get('樣品英文名稱','')),str(r.get('食品分類',''))]
    simplified=simplify_names(list(dict.fromkeys(x for x in names if x)))
    foods=[]
    for key,group in groups.items():
        r=group[0]; original=str(r.get('樣品名稱','')).strip()
        if not original: continue
        name=simplified.get(original,original)
        aliases=[simplified.get(str(r.get('俗名','')),str(r.get('俗名',''))),str(r.get('樣品英文名稱',''))]
        aliases=[x for x in aliases if x]
        waste=float(r.get('廢棄率') or 0); edible=max(0,min(1,1-waste/100 if waste>1 else 1-waste))
        values={}
        for row in group:
            item=str(row.get('分析項','')).strip(); code=TW_NUTRIENT_MAP.get(item)
            if not code: continue
            amount=row.get('每100克含量')
            if amount in (None,''): continue
            try: value=float(str(amount).replace(',',''))
            except: continue
            target=USDA_UNITS[code]; unit=str(row.get('含量單位','g')).lower().replace('µg','ug')
            converted=convert_unit(value,unit,target)
            if converted is not None: values[code]=converted
        if not values: continue
        english_name=str(r.get('樣品英文名稱','')).strip() or None
        category_original=str(r.get('食品分類','')).strip() or '其他食品'
        category_zh=simplified.get(category_original,category_original)
        source={'kind':'imported','identifier':f"taiwan-fda:{key}",'title':'Taiwan FDA 食品營養成分資料集','titleZh':'台湾 FDA 食品营养成分资料集','titleEn':'Taiwan FDA Food Nutrition Database','license':'Open Government Data License v1.0','sourceURL':'https://data.gov.tw/dataset/8543','retrievedAt':now_iso()}
        foods.append(make_food(stable_uuid('taiwan',key),name,category_zh,[nutrient(k,v) for k,v in sorted(values.items())],source,aliases=aliases,edible=edible,name_zh=name,name_en=english_name,name_zh_origin='taiwanFDA',category_zh=category_zh,category_en=category_original))
    return foods



def deduplicate_foods(foods):
    result=[]
    seen=set()
    for food in foods:
        key=normalize_name(food['name'])
        if key in seen: continue
        seen.add(key)
        result.append(food)
    return result

def load_translation_cache(path):
    raw=Path(path)
    data=json.load(open(raw,encoding='utf-8'))
    if data.get('schemaVersion') != 1:
        raise ValueError(f"unsupported translation cache schema: {data.get('schemaVersion')}")
    entries=data.get('entries')
    if not isinstance(entries,dict) or not entries:
        raise ValueError('translation cache has no entries')
    data['_file_sha256']=hashlib.sha256(raw.read_bytes()).hexdigest()
    return data

def taiwan_name_reference(path):
    reference={}
    for food in load_taiwan(path):
        english=food.get('nameEn')
        chinese=food.get('nameZh')
        if english and chinese:
            reference[normalize_name(english)]=chinese
    return reference

def apply_localizations(foods, translation_cache, taiwan_reference=None):
    taiwan_reference=taiwan_reference or {}
    translations=translation_cache['entries']
    counts={'curated':0,'taiwanFDA':0,'localMachineTranslation':0,'original':0,'missing':0}
    for food in foods:
        if food.get('nameZh'):
            origin=food.get('nameZhOrigin') or 'curated'
            food['nameZhOrigin']=origin
            counts[origin]=counts.get(origin,0)+1
            continue
        english=food.get('nameEn') or food.get('name')
        taiwan_name=taiwan_reference.get(normalize_name(english))
        if taiwan_name:
            food['nameZh']=taiwan_name
            food['nameZhOrigin']='taiwanFDA'
            counts['taiwanFDA']+=1
            continue
        translated=translations.get(english)
        if not translated or not translated.get('nameZh'):
            counts['missing']+=1
            continue
        food['nameZh']=translated['nameZh']
        origin=translated.get('origin','localMachineTranslation')
        food['nameZhOrigin']=origin if origin in ('curated','taiwanFDA','localMachineTranslation','original') else 'localMachineTranslation'
        counts[food['nameZhOrigin']]=counts.get(food['nameZhOrigin'],0)+1
    if counts['missing']:
        missing=[f.get('nameEn') or f.get('name') for f in foods if not f.get('nameZh')]
        raise ValueError(f"{counts['missing']} foods are missing Chinese names; first entries: {missing[:5]}")
    return counts

def build_sqlite(foods, output, manifest, source_meta, translation_meta=None):
    output.parent.mkdir(parents=True,exist_ok=True)
    if output.exists(): output.unlink()
    db=sqlite3.connect(output)
    db.executescript('''
    PRAGMA journal_mode=OFF; PRAGMA synchronous=OFF;
    CREATE TABLE foods(id TEXT PRIMARY KEY,name TEXT NOT NULL,name_zh TEXT,name_en TEXT,name_zh_origin TEXT,category TEXT,category_zh TEXT,category_en TEXT,source_title TEXT,search_priority INTEGER DEFAULT 0,canonical_group_id TEXT,pinyin TEXT,preparation_state TEXT,data_quality TEXT,commonality REAL,payload TEXT NOT NULL);
    CREATE VIRTUAL TABLE food_search USING fts5(food_id UNINDEXED,terms,tokenize='unicode61');
    CREATE TABLE catalog_meta(key TEXT PRIMARY KEY,value TEXT);
    ''')
    deduped=[]
    seen=set()
    for food in foods:
        key=normalize_name(food['name'])
        if key in seen: continue
        seen.add(key)
        deduped.append(food)
    for food in deduped:
        db.execute('INSERT OR REPLACE INTO foods VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',(food['id'],food['name'],food.get('nameZh'),food.get('nameEn'),food.get('nameZhOrigin'),food['category'],food.get('categoryZh'),food.get('categoryEn'),food['source']['title'],int(food.get('searchPriority',0)),food.get('canonicalGroupID'),' '.join(food.get('pinyin',[])),food.get('preparationState'),food.get('dataQuality'),float(food.get('commonality',0)),json.dumps(food,ensure_ascii=False,separators=(',',':'))))
        # Nutrients and servings already live inside the canonical JSON payload.
        # The runtime only queries payload, FTS and metadata, so duplicating them
        # in relational tables would add tens of megabytes with no read benefit.
        db.execute('INSERT INTO food_search(food_id,terms) VALUES(?,?)',(food['id'],search_terms([food.get('nameZh'),food.get('nameEn'),food['name']]+food['aliases']+food.get('pinyin',[]))))
    localized_zh=sum(1 for f in deduped if f.get('nameZh'))
    localized_en=sum(1 for f in deduped if f.get('nameEn'))
    origin_counts={origin:sum(1 for f in deduped if f.get('nameZhOrigin')==origin) for origin in ('curated','taiwanFDA','localMachineTranslation','original')}
    missing_zh=len(deduped)-localized_zh
    if missing_zh:
        raise ValueError(f'catalog contains {missing_zh} foods without Chinese names')
    meta_values={'schema_version':'4','record_count':str(len(deduped)),'name_zh_count':str(localized_zh),'name_en_count':str(localized_en),'name_zh_curated_count':str(origin_counts['curated']),'name_zh_taiwan_count':str(origin_counts['taiwanFDA']),'name_zh_machine_count':str(origin_counts['localMachineTranslation']),'name_zh_missing_count':'0','translation_cache_version':str((translation_meta or {}).get('schemaVersion','')),'translation_cache_sha256':(translation_meta or {}).get('_file_sha256',''),'translation_source_sha256':(translation_meta or {}).get('sourceSHA256',''),'generated_at':now_iso(),'storage_profile':'payload_fts_only','prepared_dish_count':str(sum(1 for f in deduped if f.get('preparationState')=='prepared')),**source_meta}
    for k,v in meta_values.items():
        db.execute('INSERT OR REPLACE INTO catalog_meta VALUES(?,?)',(k,str(v)))
    db.commit(); db.execute('VACUUM'); db.close()
    manifests={
      'schemaVersion':4,'generatedAt':now_iso(),'recordCount':len(deduped),'nameZhCount':localized_zh,'nameEnCount':localized_en,'nameZhCuratedCount':origin_counts['curated'],'nameZhTaiwanCount':origin_counts['taiwanFDA'],'nameZhMachineCount':origin_counts['localMachineTranslation'],'nameZhMissingCount':0,'translationCacheVersion':(translation_meta or {}).get('schemaVersion'),'translationCacheSHA256':(translation_meta or {}).get('_file_sha256'),'translationSourceSHA256':(translation_meta or {}).get('sourceSHA256'),'preparedDishCount':sum(1 for f in deduped if f.get('preparationState')=='prepared'),
      'database':{'path':str(output.relative_to(ROOT) if output.is_relative_to(ROOT) else output),'sha256':hashlib.sha256(output.read_bytes()).hexdigest(),'bytes':output.stat().st_size},
      'sources':[{'name':k,'version':v,'license':('Public Domain' if k.startswith('usda') else 'Open Government Data License v1.0' if k=='taiwan_fda' else 'Curated internal data'),'url':('https://fdc.nal.usda.gov/' if k.startswith('usda') else 'https://data.gov.tw/dataset/8543' if k=='taiwan_fda' else '')} for k,v in source_meta.items()]
    }
    manifest.parent.mkdir(parents=True,exist_ok=True)
    manifest.write_text(json.dumps(manifests,ensure_ascii=False,indent=2)+'\n')

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--foundation',required=True); ap.add_argument('--sr-legacy',required=True); ap.add_argument('--fndds',required=True)
    ap.add_argument('--taiwan-file',dest='taiwan_reference'); ap.add_argument('--taiwan-reference',dest='taiwan_reference'); ap.add_argument('--seed',default=str(DEFAULT_SEED)); ap.add_argument('--overlay',default=str(DEFAULT_OVERLAY)); ap.add_argument('--translation-cache',default=str(DEFAULT_TRANSLATIONS)); ap.add_argument('--prepared-overlay',default=str(DEFAULT_PREPARED))
    ap.add_argument('--output',default=str(ROOT/'Packages/NutritionKit/Sources/NutritionKit/Resources/Catalog.sqlite'))
    ap.add_argument('--manifest',default=str(ROOT/'Packages/NutritionKit/Sources/NutritionKit/Resources/catalog-manifest.json'))
    args=ap.parse_args()
    seed_foods=load_seed(Path(args.seed),Path(args.overlay))
    prepared_foods=load_prepared_overlay(Path(args.prepared_overlay),seed_foods)
    foods=prepared_foods + seed_foods
    foods += load_usda(Path(args.foundation),'foundation','USDA FoodData Central Foundation Foods 2026-04-30')
    foods += load_usda(Path(args.sr_legacy),'sr','USDA FoodData Central SR Legacy 2018-04')
    foods += load_usda(Path(args.fndds),'fndds','USDA FoodData Central FNDDS 2021-2023')
    meta={'seed':'NutritionDiary curated seed','usda_foundation':'2026-04-30','usda_sr_legacy':'2018-04','usda_fndds':'2021-2023','prepared_overlay':'2026-10-19-v1'}
    taiwan_reference={}
    if args.taiwan_reference:
        taiwan_reference=taiwan_name_reference(args.taiwan_reference); meta['taiwan_fda']='included as Chinese-name reference only'
    else:
        meta['taiwan_fda']='not included as reference; local translation cache provides full coverage'
    translation_cache=load_translation_cache(args.translation_cache)
    foods=deduplicate_foods(foods)
    counts=apply_localizations(foods,translation_cache,taiwan_reference)
    out=Path(args.output); out.parent.mkdir(parents=True,exist_ok=True)
    build_sqlite(foods,out,Path(args.manifest),meta,translation_cache)
    print(f'built {out} with manifest {args.manifest}; localization={counts}')

if __name__=='__main__': main()
