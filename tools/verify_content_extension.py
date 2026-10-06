#!/usr/bin/env python3
"""Exercise real add-on content in an isolated copy; install nothing in the game."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import shutil
import tempfile
from verify_beta_stability import ROOT, source_manifest, copy_snapshot, private_environment, run_check, changed_files


def write(path: Path, value) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')


def install_fixture(project: Path) -> None:
    folder = project / 'assets/content/beta.fixture'
    folder.mkdir()
    character = json.loads((project / 'assets/content/core/characters.json').read_text())['characters'][2]
    character.update(id='beta.fixture:ninth', title='TESTWACHE', detail='Zusätzliche Prüffigur', hp=93, capacity=7,
                     visual_profile='ivo', motion_profile='branko', dance_profile='levin', voice_profile='nora', unlocked=True)
    character.pop('starter_slot', None)
    item = {'id':'beta.fixture:copper', 'label':'Kupferprobe', 'color':'#cb9968', 'inventory_order':13,
            'storage':True, 'cargo':True, 'art':{'kind':'sprite','texture':'res://assets/workers/material_props.png','region':[48,0,24,24]}}
    recipe = {'id':'beta.fixture:copper_kit','kind':item['id'],'label':'KUPFERPROBE','cost':{'steel':1,'scrap':1},
              'time':0.2,'amount':2,'note':'Prüfplan für zusätzliche Inhalte',
              'art':{'texture':'res://assets/ui/crafting/crafting_items_v1.png','region':[1024,512,512,512]}}
    environment = json.loads((project / 'assets/environments/catalog.json').read_text())['environments'][1]
    environment.update(id='beta.fixture:yard',title='Prüfhof',detail='Zusätzlicher Prüfschauplatz',background_profile='ash_foundry',surface_profile='ash_foundry')
    categories={'characters':[character],'items':[item],'workshop_recipes':[recipe],'environments':[environment]}
    for kind, entries in categories.items(): write(folder / f'{kind}.json',{kind:entries})
    german = ['TESTWACHE','Zusätzliche Prüffigur','Kupferprobe','KUPFERPROBE','Prüfplan für zusätzliche Inhalte','Prüfhof','Zusätzlicher Prüfschauplatz']
    english = ['TEST GUARD','Additional test character','Copper sample','COPPER SAMPLE','Test recipe for additional content','Test yard','Additional test environment']
    write(folder/'pack.json',{'schema':1,'id':'beta.fixture','version':'1','requires':[{'id':'bunkercrew.core','version':'1'}],
                            'catalogs':{kind:{'path':f'res://assets/content/beta.fixture/{kind}.json','field':kind} for kind in categories},
                            'translations':{'de':dict(zip(german,german)),'en':dict(zip(german,english))}})
    manifest_path=project/'assets/content/packs.json'
    manifest=json.loads(manifest_path.read_text())
    manifest['packs'].append('res://assets/content/beta.fixture/pack.json')
    write(manifest_path,manifest)


def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot',default='godot')
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--capture',action='store_true')
    args=parser.parse_args()
    godot=shutil.which(args.godot)
    if not godot: parser.error('Godot 4.7.2 is required')
    output=args.output.resolve()
    if output.is_relative_to(ROOT) and not output.is_relative_to(ROOT/'artifacts'): parser.error('Reports must be under artifacts/')
    output.mkdir(parents=True,exist_ok=False)
    original=source_manifest(ROOT)
    write(output/'source-inputs.json',original)
    report={'success':False,'runs':[],'scope':'Disposable startup pack with ninth character, four declared profiles, new resource, sixth recipe and reused reviewed environment layers. Prepared states; no permanent fixture content, profile writes or WAN/native Windows claim.'}
    try:
        with tempfile.TemporaryDirectory(prefix='bunkercrew-content-extension-') as temporary:
            base=Path(temporary)
            project=base/'project'
            copy_snapshot(ROOT,project,original)
            install_fixture(project)
            env=private_environment(base/'profiles',godot)
            headless=[godot,'--headless','--audio-driver','Dummy','--path',str(project)]
            def execute(name,command,timeout=180):
                entry={'name':name,**run_check(command,project,env,output/(name+'.log'),timeout)}
                report['runs'].append(entry)
                write(output/'result.json',report)
                print(('PASS ' if entry['success'] else 'FAIL ')+name,flush=True)
                if not entry['success']: raise RuntimeError('Failed '+name)
            execute('import',headless+['--editor','--recovery-mode','--import','--quit'])
            common=['--','--no-profile-save','--no-upnp']
            execute('preflight',headless+['--script','tests/content_pack_preflight.gd']+common+[f'--content-report={output / "content.json"}'])
            execute('registry',headless+['--script','tests/content_registry_test.gd']+common)
            execute('characters',headless+['--script','tests/character_extension_test.gd']+common+['--extension-id=beta.fixture:ninth'])
            execute('items_crafting',headless+['--script','tests/item_crafting_catalog_test.gd']+common+['--extension-fixture'])
            if (project/'tests/scenario_content_extension_test.gd').exists():
                execute('scenario',headless+['--script','tests/scenario_content_extension_test.gd']+common+['--extension-fixture'])
            if (project/'tests/campaign_content_compatibility_test.gd').exists():
                execute('campaign_content',headless+['--script','tests/campaign_content_compatibility_test.gd']+common+['--expect-addon'])
            execute('speech',headless+['--script','tests/worker_speech_bubbles_test.gd']+common)
            if args.capture:
                graphical=[godot,'--audio-driver','Dummy','--path',str(project)]
                execute('crafting_capture',graphical+['--script','tests/item_crafting_catalog_test.gd']+common+['--extension-fixture','--capture'])
                shutil.copytree(project/'artifacts/item-crafting-captures',output/'captures')
                if (project/'tests/content_presentation_gallery.gd').exists():
                    execute('content_presentation_capture',graphical+['--script','tests/content_presentation_gallery.gd']+common+['--capture','--extension-id=beta.fixture:ninth','--output=res://artifacts/content-presentation-captures'])
                    shutil.copytree(project/'artifacts/content-presentation-captures',output/'speech-captures')
            report['content']=json.loads((output/'content.json').read_text())
            report['source_changes_during_run']=changed_files(original,source_manifest(ROOT))
            if report['source_changes_during_run']: raise RuntimeError('Live source changed during verification')
            report['success']=True
    except Exception as error:
        report['error']=str(error)
    write(output/'result.json',report)
    return 0 if report['success'] else 1


if __name__=='__main__': raise SystemExit(main())
