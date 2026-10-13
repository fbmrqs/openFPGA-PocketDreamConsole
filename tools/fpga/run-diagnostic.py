"""Collect independent checks, then build and install only qualified packages."""
from pathlib import Path
import argparse, fcntl, json, os, plistlib, subprocess, sys, time

root=Path(__file__).resolve().parents[2]
card=Path('/Volumes/POCKET')
card_uuid=None

def save(filename, **values):
    path=root/filename
    temporary=path.with_suffix('.tmp')
    temporary.write_text(json.dumps(values,indent=2)+'\n')
    temporary.replace(path)

def run(name, command, env=None):
    with (root/(name+'.log')).open('w') as output:
        process=subprocess.Popen(command,cwd=root,stdout=output,stderr=subprocess.STDOUT,env=env,start_new_session=True)
        global active_process,active_name
        active_process,active_name=process,name
        save('active-command.json',name=name,pid=process.pid,started=time.time())
        while process.poll() is None:
            monitor()
            time.sleep(5)
        result=process.returncode
    (root/(name+'.exit')).write_text(str(result)+'\n')
    return result

def same_card():
    if not card_uuid:return False
    try:
        info=plistlib.loads(subprocess.check_output(['diskutil','info','-plist',str(card)],stderr=subprocess.DEVNULL))
        return info.get('VolumeUUID')==card_uuid and info.get('MountPoint')==str(card) and info.get('Writable')
    except (subprocess.CalledProcessError,plistlib.InvalidFileException):
        return False

def alert(title, message):
    script='on run argv\nactivate\ndisplay alert (item 1 of argv) message (item 2 of argv) buttons {"OK"} default button "OK"\nend run'
    save('window-alert-status.json',state='displaying')
    result=subprocess.run(['/usr/bin/osascript','-e',script,title,message],capture_output=True,text=True)
    save('window-alert-status.json',state='dismissed' if result.returncode==0 else 'failed',returncode=result.returncode,error=result.stderr.strip())


jobs={}

def start_job(name,command,component=None):
    output=(root/(name+'.log')).open('w')
    if component:
        subprocess.run([sys.executable,'tools/fpga/evidence.py','begin',component],cwd=root,check=True)
    process=subprocess.Popen(command,cwd=root,stdout=output,stderr=subprocess.STDOUT,start_new_session=True)
    jobs[name]={'process':process,'output':output,'component':component,'state':'running'}
    monitor()


def monitor():
    for name,job in jobs.items():
        if job['state']!='running':continue
        code=job['process'].poll()
        if code is None:continue
        job['output'].close()
        if code==0 and job['component']:
            code=subprocess.run([sys.executable,'tools/fpga/evidence.py','end',job['component']],cwd=root).returncode
        job.update(state='passed' if code==0 else 'failed',returncode=code)
        (root/(name+'.exit')).write_text(str(code)+'\n')
    save('validation-jobs.json',jobs={name:{'pid':job['process'].pid,'state':job['state'],
        'returncode':job.get('returncode'),'log':str(root/(name+'.log'))}for name,job in jobs.items()})


def wait_jobs(names):
    while any(jobs[name]['state']=='running' for name in names):
        monitor();time.sleep(5)
    monitor()


def failures(names):
    return {name:str(root/(name+'.log')) for name in names if jobs[name]['state']!='passed'}


def install_package(library):
    label='library' if library else 'display'
    command=[sys.executable,'tools/package_native.py','--experimental']+(['--rom-library'] if library else [])
    package=root/('dist/pocket-dc-native-library' if library else 'dist/pocket-dc-native-experimental')
    if run(label+'-package',command):raise RuntimeError(label+' package validation failed')
    if run(label+'-package-test',[sys.executable,'tests/native_package.py',str(package)]):raise RuntimeError(label+' package test failed')
    status='diagnostic-'+label+'-install-status.json'
    if not same_card():
        save(status,state='needs_card',card=str(card))
        alert('Pocket '+label+' test needs the card','The '+label+' package passed validation. Reconnect the Pocket card and return to the chat for verified installation. The working card core is preserved.')
        return False
    save(status,state='installing',card=str(card))
    if run(label+'-install',command+['--install-to',str(card)]):raise RuntimeError(label+' installation failed')
    subprocess.run(['sync'],check=True)
    if not same_card():raise RuntimeError('Card disconnected during '+label+' installation')
    save(status,state='installed',card=str(card),writes_flushed=True,ejected=False,hardware_test_pending=True)
    if library:
        manifest=json.loads((package/'native-experimental-manifest.json').read_text())
        sys.path.insert(0,str(root/'tools'))
        from rom_library import NATIVE_ROMS
        labels={rom.key:rom.label for rom in NATIVE_ROMS}
        message='Installed and verified extra ROMs: '+', '.join(labels[key] for key in manifest['rom_library'])+'.'
        if manifest['excluded_roms']:message+='\n\nFailed profiles excluded: '+', '.join(labels[key] for key in manifest['excluded_roms'])+'. See their validation logs.'
        message+='\n\nOpen PocketDreamLibraryTest or PocketDreamLibraryTestExtra. Hardware confirmation is pending. The unsupported dumps remain under Assets/pdc/dumps/Unsupported.'
        alert('Pocket verified game library is ready',message)
    else:
        alert('Pocket display refinement is ready','The display refinement is installed, verified and flushed. Check black startup, display filters and the Pot Pit dog shadow: Pink → Venture (3) → Pot Pit (4) → Enter twice.\n\nThe extra-ROM checks are independent. Failed profiles will be omitted. Hardware confirmation is pending.')
    return True


def main():
    save('diagnostic-build-status.json',state='validating',clock_khz=98304,
        change='CPU operand/address timing; prepared framebuffer space; display fixes and ROM profiles')
    save('diagnostic-install-status.json',state='waiting_for_package',card=str(card))
    start_job('components',['bash','tools/fpga/test.sh'])
    start_job('clock-smoke',['bash','tools/fpga/slow-clock-test.sh'])
    start_job('pocket-pink',['bash','tools/fpga/pocket-system-test.sh','pdc_pink.u2','1800'])
    model=root/'build/rtl/system-pocket/Vpdc_system'
    # The Pink job builds the shared model. Its first frames prove it started.
    while jobs['pocket-pink']['state']=='running':
        text=(root/'pocket-pink.log').read_text(errors='replace')
        if ': 10 frames,' in text:break
        monitor();time.sleep(5)
    if model.exists():
        start_job('pocket-pdc100',[str(model),'pdc100.bin','1800','paced'],'system-pdc100-pocket')
    wait_jobs(['components'])
    if model.exists() and (root/'build/rtl/rom-check-full/Vpdc_rom_check').exists():
        start_job('rom-library',[sys.executable,'tools/fpga/library-test.py'])
    required=['components','clock-smoke','pocket-pink']
    if 'pocket-pdc100' in jobs:required.append('pocket-pdc100')
    wait_jobs(required)
    core_errors=failures(required)
    if 'pocket-pdc100' not in jobs:core_errors['pocket-pdc100']='Shared Pocket simulation model did not build.'
    installed=False;timing_error=None
    if not core_errors:
        sys.path.insert(0,str(root/'tools/fpga'))
        from evidence import require
        for name in ('components','system-pink-pocket','system-pdc100-pocket'):require(name)
        save('diagnostic-build-status.json',state='building',clock_khz=98304,core_checks_passed=True)
        env=dict(os.environ,PDC_QUARTUS_VOLUME='pdc-quartus-25.1',PDC_QUARTUS_EMULATOR='qemu')
        if run('quartus',['bash','tools/fpga/quartus.sh','native'],env):
            timing_error='FPGA build/timing failed; see '+str(root/'quartus.log')
        # The combined library package includes both original ROMs and display
        # changes. Its separate entries preserve the confirmed working core.
    save('diagnostic-build-status.json',state='collecting_library',core_failures=core_errors,
        timing_error=timing_error,display_installed=installed)
    if 'rom-library' in jobs:wait_jobs(['rom-library'])
    library_path=root/'build/rom-library-validation.json'
    library=json.loads(library_path.read_text())if library_path.exists()else{}
    library_installed=False
    if not core_errors and not timing_error and library.get('completed') and library.get('roms'):
        library_installed=install_package(True)
        installed=library_installed
    if core_errors or timing_error:
        save('diagnostic-build-status.json',state='blocked',core_failures=core_errors,timing_error=timing_error,
            roms_passed=list(library.get('roms',{})),rom_failures=library.get('failures',{}))
        save('diagnostic-install-status.json',state='blocked',card=str(card),display_installed=False,
            core_failures=core_errors,timing_error=timing_error,roms_passed=list(library.get('roms',{})),rom_failures=library.get('failures',{}))
        print('Build failed; exact results saved for the hourly repair follow-up. '
              'No new core installed; the working core is preserved.',flush=True)
    else:
        save('diagnostic-build-status.json',state='complete',hardware_verified=False,rom_failures=library.get('failures',{}))
        save('diagnostic-install-status.json',state='installed'if installed else 'needs_card',card=str(card),
            display_installed=False,library_installed=library_installed,writes_flushed=installed,
            ejected=False,rom_failures=library.get('failures',{}))
        if not library.get('roms'):
            print('No additional ROM passed; results saved for the hourly repair follow-up.',flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--card',type=Path,default=card)
    parser.add_argument('--card-uuid',required=True,help='Previously verified card volume UUID.')
    arguments=parser.parse_args();card=arguments.card;card_uuid=arguments.card_uuid
    lock=(root/'diagnostic-run.lock').open('a')
    try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    except BlockingIOError:raise SystemExit('A diagnostic runner already owns this workspace; leave it running.')
    try:main()
    except Exception as error:
        save('diagnostic-build-status.json',state='failed',reason=str(error))
        save('diagnostic-install-status.json',state='blocked',reason=str(error),
            display_install=json.loads((root/'diagnostic-display-install-status.json').read_text())if(root/'diagnostic-display-install-status.json').exists()else None)
        print('Failure saved for the hourly repair follow-up: '+str(error),flush=True)
        raise
