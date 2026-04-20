#!/usr/bin/env python3
import os
import shutil
import sys
# Include the virtual environment site-packages in sys.path
here = os.path.dirname(os.path.realpath(__file__))
if not os.path.exists(os.path.join(here, '.venv')):
	print('Python environment not setup')
	exit(1)
sys.path.insert(
	0,
	os.path.join(
		here,
		'.venv',
		'lib',
		'python' + '.'.join(sys.version.split('.')[:2]), 'site-packages'
	)
)
import logging
import random
import string
from warlock_manager.apps.steam_app import SteamApp
from warlock_manager.services.http_service import HTTPService
from warlock_manager.config.ini_config import INIConfig
from warlock_manager.config.properties_config import PropertiesConfig
from warlock_manager.config.unreal_config import UnrealConfig
from warlock_manager.libs.app_runner import app_runner
from warlock_manager.libs.firewall import Firewall
from warlock_manager.libs import utils
from warlock_manager.formatters.cli_formatter import cli_formatter
from warlock_manager.mods.warlock_nexus_mod import WarlockNexusMod
# To allow running as a standalone script without installing the package, include the venv path for imports.
# This will set the include path for this path to .venv to allow packages installed therein to be utilized.
#
# IMPORTANT - any imports that are needed for the script to run must be after this,
# otherwise the imports will fail when running as a standalone script.


# Import the appropriate type of handler for the game installer.
# Common options are:
# from warlock_manager.apps.base_app import BaseApp

# Import the appropriate type of handler for the game services.
# Common options are:
# from warlock_manager.services.base_service import BaseService
# from warlock_manager.services.rcon_service import RCONService
# from warlock_manager.services.socket_service import SocketService

# Import the various configuration handlers used by this game.
# Common options are:
# from warlock_manager.config.cli_config import CLIConfig
# from warlock_manager.config.json_config import JSONConfig

# Load the application runner responsible for interfacing with CLI arguments
# and providing default functionality for running the manager.

# If your script manages the firewall, (recommended), import the Firewall library

# Utilities provided by Warlock that are common to many applications

# Useful in some games

# Select the baseline for mod support
# from warlock_manager.mods.base_mod import BaseMod


class GameMod(WarlockNexusMod):
	pass


class GameApp(SteamApp):
	"""
	Game application manager
	"""

	def __init__(self):
		super().__init__()

		self.name = 'Palworld'
		self.desc = 'Palworld Dedicated Server'
		self.steam_id = '2394010'
		self.service_handler = GameService
		self.mod_handler = GameMod
		self.service_prefix = 'palworld-'

		self.configs = {
			'manager': INIConfig('manager', os.path.join(utils.get_app_directory(), '.settings.ini'))
		}
		self.load()

	def first_run(self) -> bool:
		"""
		Perform any first-run configuration needed for this game

		:return:
		"""
		if os.geteuid() != 0:
			logging.error('Please run this script with sudo to perform first-run configuration.')
			return False

		super().first_run()

		# Create necessary directories if applicable
		utils.makedirs(os.path.join(utils.get_app_directory(), 'Configs'))
		utils.makedirs(os.path.join(utils.get_app_directory(), 'Packages'))

		# Install the game with Steam.
		# It's a good idea to ensure the game is installed on first run.
		self.update()

		# Ensure configuration file exists, (Palworld doesn't do a great job at filling in incomplete configs)
		check_dest = os.path.join(self.get_app_directory(), 'Pal/Saved/Config/LinuxServer')
		if not os.path.exists(check_dest):
			logging.info('Creating missing Palworld configuration directory...')
			os.makedirs(check_dest)

		check_src = os.path.join(self.get_app_directory(), 'DefaultPalWorldSettings.ini')
		check_dest = os.path.join(self.get_app_directory(), 'Pal/Saved/Config/LinuxServer/PalWorldSettings.ini')
		if os.path.exists(check_src) and not os.path.exists(check_dest):
			logging.info('Copying default Palworld configuration file...')
			shutil.copy2(check_src, check_dest)
			utils.ensure_file_ownership(check_dest)

		# First run is a great time to auto-create some services for this game too
		services = self.get_services()
		if len(services) == 0:
			# No services detected, create one.
			logging.info('No services detected, creating one...')
			self.create_service('palworld-server')
		else:
			# Ensure services match new format
			for service in services:
				logging.info('Ensuring %s service file is on latest format' % service.service)
				service.build_systemd_config()
				service.reload()

		return True

	def post_update(self):
		path = os.path.join(self.get_app_directory(), 'Pal/Binaries/Linux/PalServer-Linux-Shipping')

		if os.path.exists(path):
			os.chmod(path, 0o755)

		steam_source = os.path.join(self.get_app_directory(), 'linux64/steamclient.so')
		steam_dest = os.path.join(self.get_app_directory(), 'Pal/Binaries/Linux/steamclient.so')
		if os.path.exists(steam_source) and not os.path.exists(steam_dest):
			shutil.copy2(steam_source, steam_dest)
			utils.ensure_file_ownership(steam_dest)


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
			'world': UnrealConfig('world', os.path.join(self.get_app_directory(), 'Pal/Saved/Config/LinuxServer/PalWorldSettings.ini')),
			'service': INIConfig('service', os.path.join(utils.get_app_directory(), 'Configs', 'service.%s.ini' % self.service))
		}
		self.load()

	def get_option_default(self, option: str) -> str:
		"""
		Get the default value of a configuration option

		:param option:
		:return:
		"""
		if option == 'Number Of Worker Threads Server':
			# This defaults to the number of CPUs present
			return os.cpu_count().toString()
		else:
			return super().get_option_default(option)

	def option_value_updated(self, option: str, previous_value, new_value) -> bool | None:
		"""
		Handle any special actions needed when an option value is updated
		:param option:
		:param previous_value:
		:param new_value:
		:return:
		"""
		success = None
		rebuild = False

		# Special option actions
		if option == 'Public Port':
			# Update firewall for game port change
			if previous_value:
				Firewall.remove(int(previous_value), 'UDP')
			Firewall.allow(int(new_value), 'UDP', 'Allow %s game port' % self.game.desc)
			success = True
			rebuild = True
		elif option in ('Public Lobby', 'Use Perf Threads', 'No Async Loading Thread', 'Use Muilthread For DS', 'Number Of Worker Threads Server'):
			success = True
			rebuild = True

		if rebuild:
			# For games that need to regenerate systemd to apply changes
			self.build_systemd_config()
			self.reload()
		return success

	def get_save_files(self) -> list | None:
		"""
		Get a list of save files / directories for the game server

		:return:
		"""
		return ['SaveGames']

	def get_save_directory(self) -> str | None:
		"""
		Get the save directory for the game server

		:return:
		"""
		return os.path.join(self.get_app_directory(), 'Pal', 'Saved')

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

	def get_player_count(self) -> int | None:
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

	def get_port(self) -> int | None:
		"""
		Get the primary port of the service, or None if not applicable
		:return:
		"""
		return self.get_option_value('Public Port')

	def get_game_pid(self) -> int:
		"""
		Get the primary game process PID of the actual game server, or 0 if not running
		:return:
		"""
		return self.get_pid()

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

	def get_port_definitions(self) -> list:
		"""
		Get a list of port definitions for this service
		:return:
		"""
		return [
			(self.get_port(), 'udp', '%s game port' % self.game.name),
			('REST API Port', 'tcp', '%s REST port' % self.game.name)
		]

	def get_executable(self) -> str:
		"""
		Get the full executable for this game service
		:return:
		"""
		path = os.path.join(self.get_app_directory(), 'Pal/Binaries/Linux/PalServer-Linux-Shipping')

		# Append UE arguments necessary to run the game
		path += ' Pal'

		# Append parameters for the game server
		path += ' -port=%s' % self.get_port()

		# Add arguments for the service, if applicable
		args = cli_formatter(self.configs['service'], 'flag', true_value=True, false_value=False)
		if args:
			path += ' ' + args

		return path

	def create_service(self):
		"""
		Create the systemd service for this game, including the service file and environment file
		:return:
		"""

		super().create_service()

		if not self.option_has_value('Admin Password'):
			# Generate a random password for RCON
			random_password = ''.join(random.choices(string.ascii_letters + string.digits, k=32))
			self.set_option('Admin Password', random_password)
		if not self.option_has_value('REST API Enabled'):
			self.set_option('REST API Enabled', True)


if __name__ == '__main__':
	app = app_runner(GameApp())
	app()
