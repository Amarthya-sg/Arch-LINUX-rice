#!/usr/bin/env python3
"""BlueZ pairing agent bridge for EssentialBar.

The helper registers an application-scoped Agent1 and performs Device1.Pair()
through the same D-Bus connection. BlueZ therefore sends numeric-comparison
requests to this agent instead of the desktop's separate pairing dialog.
QML and this process communicate using one JSON object per stdin/stdout line.
"""
import asyncio
import json
import sys
from typing import Any

from dbus_next import BusType, DBusError, Variant
from dbus_next.aio import MessageBus
from dbus_next.service import ServiceInterface, method

AGENT_PATH = "/org/essentialbar/BluetoothAgent"
AGENT_MANAGER_PATH = "/org/bluez"
AGENT_MANAGER_IFACE = "org.bluez.AgentManager1"
DEVICE_IFACE = "org.bluez.Device1"


class AgentBridge:
    def __init__(self) -> None:
        self.bus: MessageBus | None = None
        self.counter = 0
        self.pending: dict[str, asyncio.Future[tuple[bool, str]]] = {}
        self.pairing = False

    @staticmethod
    def emit(payload: dict[str, Any]) -> None:
        print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), flush=True)

    async def ask(self, kind: str, device: str, **details: Any) -> tuple[bool, str]:
        self.counter += 1
        request_id = str(self.counter)
        future: asyncio.Future[tuple[bool, str]] = asyncio.get_running_loop().create_future()
        self.pending[request_id] = future
        self.emit({"type": "prompt", "requestId": request_id, "kind": kind,
                   "devicePath": device, **details})
        try:
            return await asyncio.wait_for(future, timeout=120)
        except asyncio.TimeoutError as error:
            raise DBusError("org.bluez.Error.Canceled", "Pairing confirmation timed out") from error
        finally:
            self.pending.pop(request_id, None)

    def reply(self, request_id: str, accepted: bool, value: str = "") -> bool:
        future = self.pending.get(str(request_id))
        if future is None or future.done():
            return False
        future.set_result((bool(accepted), str(value)))
        return True

    def cancel_pending(self) -> None:
        for request_id, future in list(self.pending.items()):
            if not future.done():
                future.set_result((False, ""))
            self.emit({"type": "prompt_cancelled", "requestId": request_id})

    async def pair(self, device_path: str, address: str) -> None:
        if self.pairing:
            self.emit({"type": "pair_result", "devicePath": device_path,
                       "address": address, "success": False,
                       "error": "Another pairing operation is already active"})
            return
        self.pairing = True
        try:
            assert self.bus is not None
            introspection = await self.bus.introspect("org.bluez", device_path)
            obj = self.bus.get_proxy_object("org.bluez", device_path, introspection)
            device = obj.get_interface(DEVICE_IFACE)
            await device.call_pair()
            props = obj.get_interface("org.freedesktop.DBus.Properties")
            warning = ""
            try:
                await props.call_set(DEVICE_IFACE, "Trusted", Variant("b", True))
            except Exception as error:  # Pairing succeeded; trust can be retried by QML.
                warning = f"Paired, but could not mark trusted: {error}"
            self.emit({"type": "pair_result", "devicePath": device_path,
                       "address": address, "success": True, "warning": warning})
        except DBusError as error:
            self.emit({"type": "pair_result", "devicePath": device_path,
                       "address": address, "success": False,
                       "error": error.text or error.type})
        except Exception as error:
            self.emit({"type": "pair_result", "devicePath": device_path,
                       "address": address, "success": False, "error": str(error)})
        finally:
            self.pairing = False


class BluezAgent(ServiceInterface):
    def __init__(self, bridge: AgentBridge) -> None:
        super().__init__("org.bluez.Agent1")
        self.bridge = bridge

    @method()
    def Release(self):
        self.bridge.cancel_pending()
        self.bridge.emit({"type": "agent_released"})

    @method()
    async def RequestConfirmation(self, device: "o", passkey: "u"):
        accepted, _ = await self.bridge.ask(
            "confirmation", device, passkey=f"{int(passkey):06d}"
        )
        if not accepted:
            raise DBusError("org.bluez.Error.Rejected", "Pairing was declined in EssentialBar")

    @method()
    async def RequestAuthorization(self, device: "o"):
        accepted, _ = await self.bridge.ask("authorization", device)
        if not accepted:
            raise DBusError("org.bluez.Error.Rejected", "Pairing was declined in EssentialBar")

    @method()
    async def AuthorizeService(self, device: "o", uuid: "s"):
        accepted, _ = await self.bridge.ask("service", device, service=uuid)
        if not accepted:
            raise DBusError("org.bluez.Error.Rejected", "Service access was declined in EssentialBar")

    @method()
    async def RequestPasskey(self, device: "o") -> "u":
        accepted, value = await self.bridge.ask("passkey", device)
        if not accepted or not value.isdigit() or len(value) > 6:
            raise DBusError("org.bluez.Error.Rejected", "Invalid or declined passkey")
        return int(value)

    @method()
    async def RequestPinCode(self, device: "o") -> "s":
        accepted, value = await self.bridge.ask("pin", device)
        if not accepted or not value or len(value) > 16:
            raise DBusError("org.bluez.Error.Rejected", "Invalid or declined PIN")
        return value

    @method()
    def DisplayPasskey(self, device: "o", passkey: "u", entered: "q"):
        self.bridge.emit({"type": "display", "kind": "passkey",
                          "devicePath": device, "passkey": f"{int(passkey):06d}",
                          "entered": int(entered)})

    @method()
    def DisplayPinCode(self, device: "o", pincode: "s"):
        self.bridge.emit({"type": "display", "kind": "pin",
                          "devicePath": device, "passkey": pincode})

    @method()
    def Cancel(self):
        self.bridge.cancel_pending()


async def read_commands(bridge: AgentBridge) -> None:
    while True:
        line = await asyncio.to_thread(sys.stdin.readline)
        if not line:
            return
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        kind = message.get("type")
        if kind == "pair":
            asyncio.create_task(bridge.pair(str(message.get("devicePath", "")),
                                            str(message.get("address", ""))))
        elif kind == "reply":
            bridge.reply(str(message.get("requestId", "")),
                         bool(message.get("accepted", False)),
                         str(message.get("value", "")))


async def main() -> int:
    bridge = AgentBridge()
    try:
        bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
        bridge.bus = bus
        bus.export(AGENT_PATH, BluezAgent(bridge))
        introspection = await bus.introspect("org.bluez", AGENT_MANAGER_PATH)
        obj = bus.get_proxy_object("org.bluez", AGENT_MANAGER_PATH, introspection)
        manager = obj.get_interface(AGENT_MANAGER_IFACE)
        await manager.call_register_agent(AGENT_PATH, "DisplayYesNo")
        bridge.emit({"type": "ready"})
        await read_commands(bridge)
        try:
            await manager.call_unregister_agent(AGENT_PATH)
        except Exception:
            pass
        bus.disconnect()
        return 0
    except Exception as error:
        print(f"bluetooth_agent: {error}", file=sys.stderr, flush=True)
        bridge.emit({"type": "error", "message": str(error)})
        return 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
