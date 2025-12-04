#!/usr/bin/env python3
import pwd
import random
import string
from scriptlets._common.firewall_allow import *
from scriptlets._common.firewall_remove import *
from scriptlets.bz_eval_tui.prompt_yn import *
from scriptlets.bz_eval_tui.prompt_text import *
from scriptlets.bz_eval_tui.table import *
from scriptlets.bz_eval_tui.print_header import *
from scriptlets._common.get_wan_ip import *
# import:org_python/venv_path_include.py
from scriptlets.warlock.steam_app import *
from scriptlets.warlock.http_service import *
from scriptlets.warlock.ini_config import *
from scriptlets.warlock.unreal_config import *
from scriptlets.warlock.default_run import *

here = os.path.dirname(os.path.realpath(__file__))


class GameApp(SteamApp):
	"""
	Game application manager
	"""

	def __init__(self):
		super().__init__()

		self.name = 'Palworld'
		self.desc = 'Palworld Dedicated Server'
		self.steam_id = '2394010'
		self.services = ('palworld-server',)

		self.configs = {
			'manager': INIConfig('manager', os.path.join(here, '.settings.ini'))
		}
		self.load()

	def get_save_files(self) -> Union[list, None]:
		"""
		Get a list of save files / directories for the game server

		:return:
		"""
		return ['SaveGames']

	def get_save_directory(self) -> Union[str, None]:
		"""
		Get the save directory for the game server

		:return:
		"""
		return os.path.join(here, 'AppFiles', 'Pal', 'Saved')


class GameService(HTTPService):
	"""
	Service definition and handler
	"""
	def __init__(self, service: str, game: GameApp):
		"""
		Initialize and load the service definition
		:param file:
		"""
		super().__init__(service, game)
		self.service = service
		self.game = game
		self.configs = {
			'world': UnrealConfig('world', os.path.join(here, 'AppFiles/Pal/Saved/Config/LinuxServer/PalWorldSettings.ini'))
		}
		self.load()

	def is_api_enabled(self) -> bool:
		"""
		Check if API is enabled for this service
		:return:
		"""
		return (
			self.get_option_value('REST API Enabled') and
			self.get_option_value('REST API Port') != '' and
			self.get_option_value('Admin Password') != ''
		)

	def get_api_port(self) -> int:
		"""
		Get the API port from the service configuration
		:return:
		"""
		return self.get_option_value('REST API Port')

	def get_api_password(self) -> str:
		"""
		Get the API password from the service configuration
		:return:
		"""
		return self.get_option_value('Admin Password')

	def get_api_username(self) -> str:
		"""
		Get the API username from the service configuration
		:return:
		"""
		return 'admin'

	def get_player_count(self) -> Union[int, None]:
		"""
		Get the current player count on the server, or None if the API is unavailable
		:return:
		"""
		ret = self._api_cmd('/v1/api/players')
		# ret should contain 'There are N of a max...' where N is the player count.
		if ret is None:
			return None
		else:
			return len(ret['players'])

	def get_player_max(self) -> int:
		"""
		Get the maximum player count allowed on the server
		:return:
		"""
		return self.get_option_value('Server Player Max Num')

	def get_name(self) -> str:
		"""
		Get the name of this game server instance
		:return:
		"""
		return self.get_option_value('Server Name')

	def get_port(self) -> Union[int, None]:
		"""
		Get the primary port of the service, or None if not applicable
		:return:
		"""
		# The server port for Palworld is stored within the systemd service file.
		if os.path.exists('/etc/systemd/system/%s.service' % self.service):
			with open('/etc/systemd/system/%s.service' % self.service, 'r') as f:
				for line in f:
					if line.strip().startswith('ExecStart='):
						parts = line.strip().split(' ')
						for part in parts:
							if part.startswith('-port='):
								return int(part.split('=')[1])
		return None

	def get_game_pid(self) -> int:
		"""
		Get the primary game process PID of the actual game server, or 0 if not running
		:return:
		"""
		# For services that use a wrapper script, the actual game process will be different and needs looked up.
		# There's no quick way to get the game process PID from systemd,
		# so use ps to find the process based on the map name
		processes = subprocess.run([
			'ps', 'axh', '-o', 'pid,cmd'
		], stdout=subprocess.PIPE).stdout.decode().strip()
		exe = os.path.join(here, 'AppFiles/Pal/Binaries/Linux/')
		for line in processes.split('\n'):
			pid, cmd = line.strip().split(' ', 1)
			if cmd.startswith(exe):
				return int(line.strip().split(' ')[0])
		return 0

	def send_message(self, message: str):
		"""
		Send a message to all players via the game API
		:param message:
		:return:
		"""
		self._api_cmd('/v1/api/announce', 'POST', {'message': message})

	def save_world(self):
		"""
		Force the game server to save the world via the game API
		:return:
		"""
		self._api_cmd('/v1/api/save', 'POST')


def menu_first_run(game: GameApp):
	"""
	Perform first-run configuration for setting up the game server initially

	:param game:
	:return:
	"""
	print_header('First Run Configuration')

	if os.geteuid() != 0:
		print('ERROR: Please run this script with sudo to perform first-run configuration.')
		sys.exit(1)

	svc = game.get_services()[0]

	if not svc.option_has_value('Admin Password'):
		# Generate a random password for RCON
		random_password = ''.join(random.choices(string.ascii_letters + string.digits, k=32))
		svc.set_option('Admin Password', random_password)
	if not svc.option_has_value('REST API Enabled'):
		svc.set_option('REST API Enabled', True)
	if not svc.option_has_value('REST API Port'):
		svc.set_option('REST API Port', 8212)

if __name__ == '__main__':
	game = GameApp()
	run_manager(game)
