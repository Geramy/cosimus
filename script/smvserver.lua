
--[[

Copyright © 2008-2009 Andrew Yourtchenko, ayourtch@gmail.com.

Permission is hereby granted, free of charge, to any person obtaining 
a copy of this software and associated documentation files (the "Software"), 
to deal in the Software without restriction, including without limitation 
the rights to use, copy, modify, merge, publish, distribute, sublicense, 
and/or sell copies of the Software, and to permit persons to whom 
the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included 
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS 
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL 
THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR 
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, 
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE 
OR OTHER DEALINGS IN THE SOFTWARE. 

--]]

require 'serialize'
require 'async'
require 'smv_state_mgmt'
require 'asset_client'
require 'mv_smv_scene'
require 'mv_scene'
require 'simplemath'
require 'common'

zero_uuid = "00000000-0000-0000-0000-000000000000"

function cr()
  print("\n")
end

function smv_get_session(uuid)
  local sess = smv_state.sessions[vchk(uuid, "session uuid not nil", uuid ~= nil)]
  return vchk(sess, "sess not nil", sess ~= nil)
end

function smv_get_session_id_agent_id(uuid)
  local sess = smv_state.sess_id_by_agent_id[uuid]
  return (vchk(sess, "Session by agent id " .. 
                      tostring(uuid) .. " not nil", sess ~= nil))
end

function smv_next_seq(sess, p)
  sess.seq = sess.seq + 1
  fmv.SetSequenceNumber(p, sess.seq)
end

-- send an immediate ack for packet d arrived on session sess
function smv_ack_immed(sess, d)
  local p = fmv.packet_new()
  fmv.PacketAckHeader(p)
  fmv.PacketAck_PacketsBlockSize(p, 1)
  fmv.PacketAck_PacketsBlock(p, 0, fmv.GetSequenceNumber(d))

  smv_send_then_unlock(sess, p)
end

-- send the new packet d towards the session sess user
function smv_send_then_unlock(sess, p)
  local p1
  local dsize, size
  smv_next_seq(sess, p)
  fmv.FinalizePacketLength(p)
  p1 = fmv.MaybeZeroEncodePacket(p)
  -- todo - checking against stale sessions
  su.cdata_set_remote4(sess.idx, sess.remote_addr, sess.remote_port)
  su.sock_send_data(sess.idx, p1)
  -- su.print_dbuf(0, 0, p)
  dsize, size = su.dcheck(p)
  if dsize then
    print("p Dsize", dsize, " > ", size)
    print(fmv.global_id_str(p))
  end
  dsize, size = su.dcheck(p1)
  if dsize then
    print("p1 Dsize", dsize, " > ", size)
    print(fmv.global_id_str(p1))
  end
  fmv.packet_unlock(p)
  fmv.packet_unlock(p1)
end

function smv_send_region_handshake(sess)
  local p = fmv.packet_new()
  fmv.RegionHandshakeHeader(p)
  fmv.RegionHandshake_RegionInfo(p, 
      72458694, -- flags
      13, -- SimAccess
      "BlackStar sim\0", -- SimName
      zero_uuid, -- SimOwner (todo)
      0, -- IsEstateManager
      0, -- WaterHeight
      0, -- BillableFactor
      zero_uuid, -- CacheID
      zero_uuid, -- TerrainBase0
      zero_uuid, -- TerrainBase1
      zero_uuid, -- TerrainBase2
      zero_uuid, -- TerrainBase3
      zero_uuid, -- TerrainDetail0
      zero_uuid, -- TerrainDetail1
      zero_uuid, -- TerrainDetail2
      zero_uuid, -- TerrainDetail3
      0.0, -- TerrainStartHeight00
      0.3, -- TerrainStartHeight01
      0.5, -- TerrainStartHeight10
      1.0, -- TerrainStartHeight11
      0.3, -- TerrainHeightRange00
      0.2, -- TerrainHeightRange01
      0.5, -- TerrainHeightRange10
      1000.0 -- TerrainHeightRange11
     ) 
  fmv.RegionHandshake_RegionInfo2(p, 
     zero_uuid -- RegionID
     )
  smv_send_then_unlock(sess, p)
end


function smv_send_parcel_overlay(sess)
  local LAND_BLOCKS_PER_PACKET = 1024
  local sequence = 0
  local parceldata = ''
  for y = 1, 64 do
    for x = 1, 64 do
      -- fill the data about the land somewhere
      parceldata = parceldata .. '\0'
      if (#parceldata >= LAND_BLOCKS_PER_PACKET) then
        local p = fmv.packet_new()
	fmv.ParcelOverlayHeader(p)
	fmv.ParcelOverlay_ParcelData(p, sequence, parceldata)
	sequence = sequence + 1
	smv_send_then_unlock(sess, p)
	parceldata = ''
      end
    end
  end
end

function smv_get_region_handle()
  return fmv.GetRegionHandle(1000, 1000)
end

function smv_ping_check_reply(sess, ping)
 su.dlock(ping)
 smv_send_then_unlock(sess, ping)
end

function smv_send_agent_movement_complete(sess)
  local p = fmv.packet_new()
  fmv.AgentMovementCompleteHeader(p)
  fmv.AgentMovementComplete_AgentData(p, sess.AgentID, sess.SessionID)
  fmv.AgentMovementComplete_Data(p, 
     30, 30, 30, -- Position
     0,0,0, -- LookAt
     smv_get_region_handle(), -- RegionHandle
     0 -- Timestamp
     )
  fmv.AgentMovementComplete_SimData(p, "Cosimus v0.01")
  smv_send_then_unlock(sess, p)
end

function smv_send_money_balance(sess, d)
  local p = fmv.packet_new()
  local TransactionID = fmv.Get_MoneyBalanceRequest_MoneyData(d)
  fmv.MoneyBalanceReplyHeader(p)
  fmv.MoneyBalanceReply_MoneyData(p, sess.AgentID, TransactionID, 
     1, -- TransactionSuccess
     1000.0, -- MoneyBalance
     0, -- SquareMetersCredit
     0, -- SquareMetersCommitted
     "" -- Description
     )
  smv_send_then_unlock(sess, p)
end

function smv_logout_session(sess)
  local session_id = sess.SessionID
  print("Logging out session ", session_id)
  smv_state.sess_id_by_remote[sess.remote_str] = nil
  smv_state.sess_id_by_agent_id[sess.AgentID] = nil
  smv_state.sessions[session_id] = nil
  scene_remove_avatar(sess.AgentID)
end

function smv_agent_width_height(sess, d)
  local GenCounter, Height, Width = fmv.Get_AgentHeightWidth_HeightWidthBlock(d)
  print ("Agent gencounter: ", GenCounter, " width/height: ", Width, Height)
end

function smv_chat_from_viewer(sess, d)
  local AgentID, SessionID = fmv.Get_ChatFromViewer_AgentData(d)
  local Message, Type, Channel = fmv.Get_ChatFromViewer_ChatData(d)
  print("Chat from viewer type ", Type, " channel ", Channel, " message ", Message)
  if Message then
    local cmd = string.sub(Message, 1, -2)
    print("'" .. cmd .. "'")
  end
end

function smv_parcel_properties_request(sess, d)
  local AgentID, SessionID = fmv.Get_ParcelPropertiesRequest_AgentData(d)
  local SequenceID, West, South, East, North, SnapSelection = fmv.Get_ParcelPropertiesRequest_ParcelData(d)
  local bitmap = string.rep('\255', 512)
  local p = fmv.packet_new()
  fmv.ParcelPropertiesHeader(p)
  -- print("Length: ", #bitmap)
  
  fmv.ParcelProperties_ParcelData(p, 
     1, -- RequestResult
     SequenceID, -- SequenceID
     SnapSelection, -- SnapSelection
     1, -- SelfCount
     0, -- OtherCount
     1, -- PublicCount
     12345, -- LocalID (of what?)
     AgentID, -- OwnerID, temporarily set to user id for test
     false, -- IsGroupOwned
     0, -- AuctionID
     10000, -- ClaimDate
     0, -- ClaimPrice
     0, -- RentPrice
     0.0, 0.0, 0.0, -- AABBMin
     256.0, 256.0, 256.0, -- AABBMax
     bitmap, -- Bitmap
     65536, -- Area
     0, -- Status
     12345, -- SimWideMaxPrims
     33, -- SimWideTotalPrims
     250, -- MaxPrims
     200, -- TotalPrims
     150, -- OwnerPrims
     10, -- GroupPrims
     40, -- OtherPrims
     0, -- SelectedPrims
     0.0, -- ParcelPrimBonus
     0, -- OtherCleanTime
     0, -- ParcelFlags
     0, -- SalePrice
     "Dalien's parcel test\0", -- Name
     "Description of dalien's parcel here\0", -- Desc
     "http://127.0.0.1/test\0", -- MusicURL
     "http://127.0.0.1/test2\0", -- MediaURL
     0, -- MediaID
     1, -- MediaAutoScale
     zero_uuid, -- GroupID
     0, -- PassPrice
     0, -- PassHours
     0, -- Category
     zero_uuid, -- AuthBuyerID
     zero_uuid, -- SnapshotID
     0.0, 0.0, 0.0, -- UserLocation
     0.0, 0.0, 0.0, -- UserLookAt
     0, -- LandingType
     0, -- RegionPushOverride
     0, -- RegionDenyAnonymous
     0, -- RegionDenyIdentified
     0 -- RegionDenyTransacted
     )
  fmv.ParcelProperties_AgeVerificationBlock(p, 
     0 -- RegionDenyAgeUnverified
     )
  smv_send_then_unlock(sess, p)

end

function smv_estate_covenant_request(sess, d)
  local p = fmv.packet_new()
  fmv.EstateCovenantReplyHeader(p)
  fmv.EstateCovenantReply_Data(p, 
      zero_uuid, -- CovenantID
      12345, -- CovenantTimestamp
      "Test Estate Name\0", -- EstateName
      sess.AgentID -- EstateOwnerID
    )
  
  smv_send_then_unlock(sess, p)
end

function smv_parcel_dwell_request(sess, d)
  local p = fmv.packet_new()
  local AgentID, SessionID = fmv.Get_ParcelDwellRequest_AgentData(d)
  local LocalID, ParcelID = fmv.Get_ParcelDwellRequest_Data(d)
  print("Parcel dwell request: ", LocalID, ParcelID)
  fmv.ParcelDwellReplyHeader(p)
  fmv.ParcelDwellReply_AgentData(p, AgentID)
  fmv.ParcelDwellReply_Data(p, LocalID, ParcelID, 0);
  
  smv_send_then_unlock(sess, p)
end

function smv_parcel_access_list_request(sess, d)
  local p = fmv.packet_new()
  local AgentID, SessionID = fmv.Get_ParcelAccessListRequest_AgentData(d)
  local SequenceID, Flags, LocalID = fmv.Get_ParcelAccessListRequest_Data(d)
  print("Parcel ACL request: ", SequenceID, Flags, LocalID)
  fmv.ParcelAccessListReplyHeader(p)
  fmv.ParcelAccessListReply_Data(p, AgentID, SequenceID, Flags, LocalID)
  fmv.ParcelAccessListReply_ListBlockSize(p, 1)
  fmv.ParcelAccessListReply_ListBlock(p, 0, AgentID, 10000, 0)
  smv_send_then_unlock(sess, p)
end

-- CB: called when we finally got the wearables
-- a.Wearables contains the array of UUIDs of wearables or nil
-- NB: async req & session should be checked elsewhere to be non-null

function smv_cb_wearables_received(a)
  local sess = smv_get_session(a.SessionID)
  local AgentID, SessionID = sess.AgentID, sess.SessionID
  local total_wearables = 0
  local wearables = a.Wearables
  local BaseMask = 0x3fffffff -- NextOwnerMask
  local Flags = 0x3fffffff
  assert(wearables)

  local p = fmv.packet_new()
  print("Callback smv_cb_wearables_received")
  -- pretty("xxxxx", a)

  fmv.UpdateCreateInventoryItemHeader(p)
  fmv.UpdateCreateInventoryItem_AgentData(p, AgentID,
      true, -- SimApproved
      0 -- TransactionID
    )
  local totalitems = 0
  for index, i in ipairs(wearables) do
    if i.ItemID == zero_uuid then
      -- do nothing
    else
      fmv.UpdateCreateInventoryItem_InventoryDataBlock(p, totalitems, 
	      i.ItemID, 
	      i.FolderID, 
	      0,
	      i.CreatorID or AgentID, -- CreatorID
	      i.OwnerID or AgentID, -- OwnerID
	      i.GroupID, -- GroupID
	      i.BaseMask, -- BaseMask
	      i.OwnerMask, -- OwnerMask
	      i.GroupMask, -- GroupMask
	      i.EveryoneMask, -- EveryoneMask
	      i.NextOwnerMask, -- NextOwnerMask
	      i.GroupOwned, -- GroupOwned
	      i.AssetID, -- AssetID
	      i.Type, -- Type
	      i.InvType, -- InvType
	      i.Flags, -- Flags
	      i.SaleType, -- SaleType,
	      i.SalePrice, -- SalePrice
	      enzeroize(i.Name), -- Name
	      enzeroize(i.Description), -- Description
	      i.CreationDate, -- CreationDate
	      0 -- CRC
       )
      totalitems = totalitems + 1
    end
  end
  fmv.UpdateCreateInventoryItem_InventoryDataBlockSize(p,totalitems)
  smv_send_then_unlock(sess, p)

  local p = fmv.packet_new()
  fmv.AgentWearablesUpdateHeader(p)
  fmv.AgentWearablesUpdate_AgentData(p, AgentID, SessionID, 1)
  for i, item in ipairs(wearables) do
    print("Wearable #", i, item.ItemID, item.AssetID)
    fmv.AgentWearablesUpdate_WearableDataBlock(p, i-1, 
	    item.ItemID, -- ItemID
	    item.AssetID, -- AssetID
	    i-1 -- WearableType
	  )
    total_wearables = total_wearables + 1 
  end
  print("Total wearables: ", total_wearables)
  fmv.AgentWearablesUpdate_WearableDataBlockSize(p, total_wearables)
  smv_send_then_unlock(sess, p)
end

function smv_agent_wearables_request(sess)
  local AgentID, SessionID = sess.AgentID, sess.SessionID
  -- fire up an async callback
  local uuid = inventory_client_wearables_request(sess.SessionID, sess.AgentID, smv_cb_wearables_received)
  print("Wearables request async ID", uuid)
end


function smv_cb_asset_client_asset(a, asset_base)
  local sess = smv_get_session(a.SessionID)
  local p = fmv.packet_new()
  -- local MAX_SZ = 600 -- MAX_PACKET_SZ - 100
  local MAX_SZ = 1000 -- MAX_PACKET_SZ - 100
  local asset_sz = 0
  print("Transfer req reply for asset id", a.AssetID, asset_base)
  fmv.TransferInfoHeader(p)
  if asset_base then
    asset_sz = #(asset_base.Data)
    print("Item found! length:", asset_sz)
    fmv.TransferInfo_TransferInfo(p, 
      a.arg.TransferID, 
      2,  -- ChannelType
      0,  -- TargetType
      0,  -- Status
      asset_sz, -- Size
      a.arg.Params)
    smv_send_then_unlock(sess, p)
    if asset_sz <= MAX_SZ then
      print("One-shot sending!")
      p = fmv.packet_new()
      fmv.TransferPacketHeader(p)
      fmv.TransferPacket_TransferData(p, a.arg.TransferID, 
        2, -- ChannelType, 
        0, -- Packet
        1, -- Status
        asset_base.Data);
      smv_send_then_unlock(sess, p)
    else
      print("Multipacket sending!")
      local packet_num = 0
      local curr_done = 0
      while curr_done < asset_sz do
        local ass_data = string.sub(asset_base.Data, curr_done+1, curr_done + MAX_SZ)
	local status
        p = fmv.packet_new()
        fmv.TransferPacketHeader(p)
	if curr_done + #ass_data >= asset_sz then
	  status = 1
	else
	  status = 0
	end
	print("Sending xfer packet #", packet_num, #ass_data, " total bytes, for now done ", curr_done, ", status", status)
        fmv.TransferPacket_TransferData(p, a.arg.TransferID, 
          2, -- ChannelType, 
          packet_num, -- Packet
          status, -- Status
          ass_data);
        smv_send_then_unlock(sess, p)
	curr_done = curr_done + #ass_data
	packet_num = packet_num + 1
      end
    end
  else
    fmv.TransferInfo_TransferInfo(p, 
      a.arg.TransferID, a.arg.ChannelType, 
      0,  -- TargetType
      1,  -- Status
      0, -- Size
      a.arg.Params)
    print("Item not found")
    smv_send_then_unlock(sess, p)
    
  end
end

function smv_transfer_request(sess, d)
  local arg = {}

  arg.TransferID, arg.ChannelType, arg.SourceType, arg.Priority, arg.Params = fmv.Get_TransferRequest_TransferInfo(d)
  arg.AssetID = fmv.uuid_from_bytes(arg.Params)
  print("Transfer request#", arg.TransferID, "for item", arg.AssetID, "ChannelType", arg.ChannelType, "SourceType", arg.SourceType)
  -- print("Priority", Priority, "Param len:", #Params)
  asset_client_request_asset(sess.SessionID, arg.AssetID, arg, smv_cb_asset_client_asset)
end

function smv_uuid_name_request(sess, d)
  local p = fmv.packet_new()
  local bs = fmv.Get_UUIDNameRequest_UUIDNameBlockBlockSize(d)
  fmv.UUIDNameReplyHeader(p)
  fmv.UUIDNameReply_UUIDNameBlockBlockSize(p, bs)

  for i=0,bs-1 do
    local uuid = fmv.Get_UUIDNameRequest_UUIDNameBlockBlock(d, i)
    print("Request for resolving UUID for ", uuid)
    fmv.UUIDNameReply_UUIDNameBlockBlock(p, i, uuid, "Test\0", "User | example.org\0")
  end
  smv_send_then_unlock(sess, p)
end

function smv_viewer_effect(sess, d)
  local AgentID, SessionID = fmv.Get_ViewerEffect_AgentData(d)
  local bs = fmv.Get_ViewerEffect_EffectBlockSize(d)
  -- print("Viewer effect block size:", bs)
  for i=1,bs do
    local ID, AgentID, Type, Duration, Color, TypeData = fmv.Get_ViewerEffect_EffectBlock(d, i-1)
    -- print("Effect block", ID, AgentID, Type, Duration, #Color, #TypeData)
  end
end

function smv_agent_data_update(sess, d)
  local AgentID, SessionID = fmv.Get_ViewerEffect_AgentData(d)
  local p = fmv.packet_new()
  fmv.AgentDataUpdateHeader(p)
  fmv.AgentDataUpdate_AgentData(p, 
      AgentID,
      "Dalien", -- FirstName
      "Talbot | domain.com", -- LastName
      "TestGroup Title", -- GroupTitle
      AgentID, -- ActiveGroupID
      "\0\0\0\0\0\0\0\0", -- GroupPowers
      "TestGroupName" -- GroupName
      )
  smv_send_then_unlock(sess, p)
end
function smv_agent_update_received(sess, d)
  local AgentID, SessionID, 
    xBodyRotation, yBodyRotation, zBodyRotation, wBodyRotation,
    xHeadRotation, yHeadRotation, zHeadRotation, wHeadRotation,
    State,
    xCameraCenter, yCameraCenter, zCameraCenter,
    xCameraAtAxis, yCameraAtAxis, zCameraAtAxis,
    xCameraLeftAxis, yCameraLeftAxis, zCameraLeftAxis,
    xCameraUpAxis, yCameraUpAxis, zCameraUpAxis,
    Far,
    ControlFlags,
    Flags = fmv.Get_AgentUpdate_AgentData(d)
  -- print("Agent update ControlFlags =", ControlFlags, "Flags = ", Flags)
  -- boolean arithmetic would have been much more deserved here, but this will do for now
  if (ControlFlags == 524288) or (ControlFlags == 1025) then
    local dx, dy, dz = 1, 0, 0
    dx, dy, dz = math_vec_mult_quat(dx,dy,dz, 
                   xBodyRotation, yBodyRotation, zBodyRotation, wBodyRotation)
    smv_scene_move_avatar_by(AgentID, dx, dy, dz)
  end
  

  -- print("Agent update camera is at:", xCameraCenter, yCameraCenter, zCameraCenter)

end

function smv_cb_asset_upload_complete(a)
  print("Asset successfully uploaded to server!")
end

function smv_asset_upload_request(sess, d)
  -- local comment = [[
  local p = fmv.packet_new()
  local newasset = {}
  local uuid = fmv.uuid_create()
  local TransactionID, Type, Tempfile, StoreLocal, AssetData = fmv.Get_AssetUploadRequest_AssetBlock(d)
  print("Asset upload request: ", TransactionID, Type, Tempfile, StoreLocal, #AssetData)
  print("Asset Data len:", #AssetData)
  -- print("Asset Data", AssetData)
  smv_state.transactions[TransactionID] = {}
  smv_state.transactions[TransactionID].AssetID = uuid
  smv_state.assets[uuid] = newasset
  newasset.Type = Type
  newasset.Tempfile = Tempfile
  newasset.StoreLocal = StoreLocal
  newasset.AssetData = AssetData
  newasset.AssetID = uuid
  if (#AssetData > 0) then
    fmv.AssetUploadCompleteHeader(p)
    fmv.AssetUploadComplete_AssetBlock(p, uuid, Type, 1)
    asset_client_upload_asset(sess.SessionID, newasset, smv_cb_asset_upload_complete)
  else 
    fmv.RequestXferHeader(p)
    fmv.RequestXfer_XferID(p, 
      string.rep("\0", 8), -- XferID
      "blah", --  FileName
      0, -- Path
      Tempfile, -- DeleteOnCompletion
      false, -- UseBigPackets
      uuid, -- VFileID
      Type) -- VFileType
  end
  smv_send_then_unlock(sess, p)
  -- ]]
end

function smv_cb_inventory_item_created(a, Item)
  local sess = smv_get_session(a.SessionID)
  local i = Item
  local p = fmv.packet_new()
  print("Got Item/Asset IDs from smv_inv_create_inventory_item:", i.ItemID, i.AssetID)

  fmv.UpdateCreateInventoryItemHeader(p)
  fmv.UpdateCreateInventoryItem_AgentData(p, a.AgentID,
      true, -- SimApproved
      a.TransactionID -- TransactionID
    )
  fmv.UpdateCreateInventoryItem_InventoryDataBlockSize(p,1)
  fmv.UpdateCreateInventoryItem_InventoryDataBlock(p, 0, 
      i.ItemID, 
      i.FolderID, 
      a.CallbackID,
      i.CreatorID, -- CreatorID
      i.OwnerID, -- OwnerID
      i.GroupID, -- GroupID
      i.BaseMask, -- BaseMask
      i.OwnerMask, -- OwnerMask
      i.GroupMask, -- GroupMask
      i.EveryoneMask, -- EveryoneMask
      i.NextOwnerMask, -- NextOwnerMask
      i.GroupOwned, -- GroupOwned
      i.AssetID, -- AssetID
      i.Type, -- Type
      i.InvType, -- InvType
      i.Flags, -- Flags
      i.SaleType, -- SaleType,
      i.SalePrice, -- SalePrice
      enzeroize(i.Name), -- Name
      enzeroize(i.Description), -- Description
      i.CreationDate, -- CreationDate
      0 -- CRC
    )
  smv_send_then_unlock(sess, p)
end

function smv_create_inventory_item(sess, d)
  local p = fmv.packet_new()
  local AgentID, SessionID = fmv.Get_CreateInventoryItem_AgentData(d)
  local arg = {}
  
  arg.CallbackID, arg.FolderID, arg.TransactionID, arg.NextOwnerMask, arg.Type, arg.InvType, 
        arg.WearableType, arg.Name, arg.Description = fmv.Get_CreateInventoryItem_InventoryBlock(d)

  arg.Name = dezeroize(arg.Name)
  arg.Description = dezeroize(arg.Description)

  arg.AssetID = zero_uuid
  if not (arg.TransactionID == zero_uuid) and  smv_state.transactions[arg.TransactionID] then
    arg.AssetID = smv_state.transactions[arg.TransactionID].AssetID
  end

  print("TransactionID for create inventory item:", arg.TransactionID, "derived asset id", arg.AssetID)

  inventory_client_create_item(SessionID, AgentID, arg, smv_cb_inventory_item_created)
end

function smv_cb_update_inventory_item(a)
  print("Update inventory item done!")
end

function smv_update_inventory_item(sess, d)
  local AgentID, SessionID, TransactionID = fmv.Get_UpdateInventoryItem_AgentData(d)
  local sz = fmv.Get_UpdateInventoryItem_InventoryDataBlockSize(d)
  local items = {}
  items.Items = {}
  items.CallbackIDs = {}

  print("Update inventory item size", sz, "transaction id", TransactionID)
  for j=0,sz-1 do
    local i = {}
    local CallbackID

    i.ItemID, i.FolderID, CallbackID, i.CreatorID, i.OwnerID, i.GroupID, 
         i.BaseMask, i.OwnerMask, i.GroupMask, i.EveryoneMask, i.NextOwnerMask, 
	 i.GroupOwned, i.TransactionID, i.Type, i.InvType, i.Flags, i.SaleType, i.SalePrice,
	 i.Name, i.Description, i.CreationDate = fmv.Get_UpdateInventoryItem_InventoryDataBlock(d, j)
  
    i.Name = dezeroize(i.Name)
    i.Description = dezeroize(i.Description)

    print("Update item ", i.ItemID)
    if i.FolderID == zero_uuid then
      print("Zero parent = not updating")
      return
    end

    if not (TransactionID == zero_uuid) then
      i.AssetID = smv_state.transactions[TransactionID].AssetID
    end
    table.insert(items.Items, i)
    table.insert(items.CallbackIDs, CallbackID)
  end
  inventory_client_update_items(SessionID, AgentID, items, smv_cb_update_inventory_item)
end

function smv_copy_inventory_item(sess, d)
  local AgentID, SessionID = fmv.Get_CopyInventoryItem_AgentData(d)
  local sz = fmv.Get_CopyInventoryItem_InventoryDataBlockSize(d)
  for i=0,sz-1 do
    local item = {}
    item.CallbackID, item.OldAgentID, item.OldItemID, item.NewFolderID, item.NewName = fmv.Get_CopyInventoryItem_InventoryDataBlock(d, i)
    pretty("Copy item", item)
  end

end

function smv_cb_inventory_folder_created(a)
  print("The server has created a folder")
end

function smv_create_inventory_folder(sess, d)
  local p = fmv.packet_new()
  local AgentID, SessionID = fmv.Get_CreateInventoryFolder_AgentData(d)
  local FolderID, ParentID, Type, Name = fmv.Get_CreateInventoryFolder_FolderData(d)
  print("Creating folder of type ", Type, " parent ", ParentID, " name: ", Name)
  inventory_client_create_folder(SessionID, AgentID, FolderID, 
               ParentID, Type, Name, smv_cb_inventory_folder_created)
end

function smv_cb_inventory_descendents(a, desc)
  local sess = smv_get_session(a.SessionID)
  local AgentID, SessionID = sess.AgentID, sess.SessionID

  local p = fmv.packet_new()
  local total_folder_descendents = 0
  local total_item_descendents = 0
  local total_descendents = #desc.Folders + #desc.Items

  fmv.InventoryDescendentsHeader(p)
  print("DescendentsX", desc)

  for i, item in ipairs(desc.Folders) do
    if item.IsFolder then
      fmv.InventoryDescendents_FolderDataBlock(p, total_folder_descendents,
	item.ID, -- FolderID
	item.FolderID, -- PArentID
	item.Type, -- Type
	enzeroize(item.Name)) -- Name
      total_folder_descendents = total_folder_descendents + 1
    end
  end
  fmv.InventoryDescendents_FolderDataBlockSize(p, total_folder_descendents)
  print("Total Folder Descendents:", total_folder_descendents)

  for i, item in ipairs(desc.Items) do
    if not item.IsFolder then
      fmv.InventoryDescendents_ItemDataBlock(p, total_item_descendents, 
          item.ItemID, -- ItemID
  	  item.FolderID, -- FolderID
	  item.CreatorID or AgentID, -- CreatorID
	  item.OwnerID or AgentID, -- OwnerID
	  item.GroupID, -- GroupID
	  item.BaseMask, -- BaseMask
	  item.OwnerMask, -- OwnerMask
	  item.GroupMask, -- GroupMask
	  item.EveryoneMask, -- EveryoneMask
	  item.NextOwnerMask, -- NextOwnerMask
	  item.GroupOwned, -- GroupOwned
	  item.AssetID, -- AssetID
	  item.Type, -- Type
	  item.InvType, -- InvType
	  item.Flags, -- Flags
	  item.SaleType, -- SaleType
	  item.SalePrice, -- SalePrice
	  enzeroize(item.Name), -- Name
	  enzeroize(item.Description), -- Description
	  item.CreationDate, -- CreationDate
	  0) -- CRC
      total_item_descendents = total_item_descendents + 1
      if (total_item_descendents > 10) then
        fmv.InventoryDescendents_ItemDataBlockSize(p, total_item_descendents)
        fmv.InventoryDescendents_AgentData(p, AgentID, a.arg.FolderID, a.arg.OwnerID, 
              1, -- Version
              total_folder_descendents + total_item_descendents) -- Descendents
        smv_send_then_unlock(sess, p)
        print("Sent one descendants packet")
        total_item_descendents = 0
        total_folder_descendents = 0
        p = fmv.packet_new()
        fmv.InventoryDescendentsHeader(p)
        fmv.InventoryDescendents_FolderDataBlockSize(p, total_folder_descendents)
      end
    end
  end
  fmv.InventoryDescendents_ItemDataBlockSize(p, total_item_descendents)
  fmv.InventoryDescendents_AgentData(p, AgentID, a.arg.FolderID, a.arg.OwnerID, 
      1, -- Version
      -- total_folder_descendents + total_item_descendents) -- Descendents
      total_descendents) -- Descendents
  
  print("Total Item Descendents:", total_item_descendents)
  smv_send_then_unlock(sess, p)
  p = fmv.packet_new()
  fmv.InventoryDescendentsHeader(p)
  fmv.InventoryDescendents_FolderDataBlockSize(p, 0)
  fmv.InventoryDescendents_ItemDataBlockSize(p, 0)
  fmv.InventoryDescendents_AgentData(p, AgentID, a.arg.FolderID, a.arg.OwnerID, 
     1, -- Version
     0) -- Descendents
  smv_send_then_unlock(sess, p)
end


function smv_fetch_inventory_descendents(sess, d)
  local AgentID, SessionID = fmv.Get_FetchInventoryDescendents_AgentData(d)
  local arg = {}
  arg.FolderID, arg.OwnerID, arg.SortOrder, arg.FetchFolders, arg.FetchItems =
                   fmv.Get_FetchInventoryDescendents_InventoryData(d)

  print ("Fetch Descendents for ", arg.FolderID, arg.FetchFolders, arg.FetchItems, arg.SortOrder)

  inventory_client_fetch_inventory_descendents(SessionID, AgentID, arg, smv_cb_inventory_descendents)
end


function smv_agent_cached_texture(sess, d)
  local p = fmv.packet_new()
  local AgentID, SessionID, SerialNum = fmv.Get_AgentCachedTexture_AgentData(d)
  local sz = fmv.Get_AgentCachedTexture_WearableDataBlockSize(d)
  fmv.AgentCachedTextureResponseHeader(p)
  fmv.AgentCachedTextureResponse_AgentData(p, AgentID, SessionID, SerialNum)
  fmv.AgentCachedTextureResponse_WearableDataBlockSize(p, sz)
  for i=0,sz-1 do
    local ID, TextureIndex = fmv.Get_AgentCachedTexture_WearableDataBlock(d, i)
    fmv.AgentCachedTextureResponse_WearableDataBlock(p, i,
       zero_uuid, -- TextureID
       TextureIndex, -- TextureIndex
       "") -- Hostname
  end
  smv_send_then_unlock(sess, p)
end

function smv_agent_is_now_wearing(sess, d)
  local sz = fmv.Get_AgentIsNowWearing_WearableDataBlockSize(d)
  local  wearables = {}
  print("Now wearing:", sz)
  for i=0,sz-1 do
    local w = {}
    w.ItemID, w.WearableType = fmv.Get_AgentIsNowWearing_WearableDataBlock(d, i)
    print("Wearable #", i, w.ItemID, w.WearableType)
    table.insert(wearables, w)
  end
  inventory_client_update_default_wearables(sess.SessionID, sess.AgentID, wearables)
end

function smv_agent_set_appearance(sess, d)
  local AgentID, SessionID, SerialNum, Size = fmv.Get_AgentSetAppearance_AgentData(d)
  local szw = fmv.Get_AgentSetAppearance_WearableDataBlockSize(d)
  local TextureEntry = fmv.Get_AgentSetAppearance_ObjectData(d) 
  local szv = fmv.Get_AgentSetAppearance_VisualParamBlockSize(d)
  
  print("smv_agent_set_appearance for " .. AgentID .. " number " .. SerialNum .. " size " .. Size)
  print("szw: ", szw)
  print("szv: ", szv) 
  print("txe: ", #TextureEntry)
  
end

function smv_agent_animation(sess, d)
  local p = fmv.packet_new()
  local AgentID, SessionID = fmv.Get_AgentAnimation_AgentData(d)
  local sza = fmv.Get_AgentAnimation_AnimationListBlockSize(d)
  local sze = fmv.Get_AgentAnimation_PhysicalAvatarEventListBlockSize(d)

  fmv.AvatarAnimationHeader(p)
  fmv.AvatarAnimation_Sender(p, AgentID)

  for i=0,sza-1 do
    local AnimID, StartAnim = fmv.Get_AgentAnimation_AnimationListBlock(d, i)
    print("Animation ID:", AnimID, StartAnim)
    fmv.AvatarAnimation_AnimationListBlock(p, i, AnimID, 1)
  end
  fmv.AvatarAnimation_AnimationListBlockSize(p, sza)

  fmv.AvatarAnimation_AnimationSourceListBlockSize(p, 0)

  for i=0,sze-1 do
    local TypeData = fmv.Get_AgentAnimation_PhysicalAvatarEventListBlock(d, i)
    fmv.AvatarAnimation_PhysicalAvatarEventListBlock(p, i, TypeData)
  end
  fmv.AvatarAnimation_PhysicalAvatarEventListBlockSize(p, sze)
  smv_send_then_unlock(sess, p)
end

function smv_packet(idx, d)
  local gid = fmv.global_id_str(d)
  local remote_addr, remote_port = su.cdata_get_remote4(idx)
  local remote_str = remote_addr .. ':' .. tostring(remote_port)
  -- print("Got packet")
  if gid == "UseCircuitCode" then
    local circuit_code, session_id, user_id = fmv.Get_UseCircuitCode_CircuitCode(d)
    print("Circuit code: " .. tostring(circuit_code))
    print("session_id: " .. session_id)
    print("user_id: " .. user_id)
    print("smv_state:", smv_state)
    if(smv_state.sessions[session_id]) then
      print("Duplicate usecircuitcode!\n")
    else
      local sess = {}
      smv_state.sessions[session_id] = sess
      smv_state.sess_id_by_remote[remote_str] = session_id
      smv_state.sess_id_by_agent_id[user_id] = session_id

      sess.idx = idx
      sess.circuit_code = circuit_code
      sess.SessionID = session_id
      sess.AgentID = user_id
      sess.remote_addr = remote_addr
      sess.remote_port = remote_port
      sess.remote_str = remote_str
      sess.seq = 0

      smv_ack_immed(sess, d)
      smv_send_region_handshake(sess)
    end
  else 
    local sess = smv_state.sessions[smv_state.sess_id_by_remote[remote_str]]
    if sess then
      sess.idx = idx
      if gid == "PacketAck" then
      elseif fmv.IsReliable(d) then
        -- print("Got a reliable packet!\n")
        smv_ack_immed(sess, d)
      end
      if gid == "PacketAck" then
        -- do nothing
      elseif gid == "CompleteAgentMovement" then
        smv_scene_add_avatar(sess.SessionID, sess.AgentID, {}, "Fixme | example.com", 30, 30, 2)
        smv_send_agent_movement_complete(sess)
	smv_send_parcel_overlay(sess)
	smv.SendLayerData(sess)
        -- smv_agent_wearables_request(sess)
	-- smv_parcel_properties_request(sess, d)

      elseif gid == "StartPingCheck" then
        smv_ping_check_reply(sess, d)
      elseif gid == "CompletePingCheck" then
        smv_ping_check_reply(sess, d)
        -- smv_agent_wearables_request(sess)
      elseif gid == "AgentDataUpdateRequest" then
        -- smv_agent_data_update(sess, d)
      elseif gid == "AgentUpdate" then
        smv_agent_update_received(sess, d)
        -- frequent agent updates go here
      elseif gid == "AgentHeightWidth" then
        smv_agent_width_height(sess, d)
      elseif gid == "AgentWearablesRequest" then
        smv_agent_wearables_request(sess)
      elseif gid == "AgentAnimation" then
        smv_agent_animation(sess, d)
      elseif gid == 'SomeFooBarZZZZZ' then
	smv_x_send_avatar_data(sess)
      elseif gid == "AssetUploadRequest" then
        smv_asset_upload_request(sess, d)
      elseif gid == "CreateInventoryItem" then
        smv_create_inventory_item(sess, d)
      elseif gid == "CreateInventoryFolder" then
        smv_create_inventory_folder(sess, d)
      elseif gid == "UpdateInventoryItem" then
        smv_update_inventory_item(sess, d)
      elseif gid == "CopyInventoryItem" then
        smv_copy_inventory_item(sess, d)
      elseif gid == "FetchInventoryDescendents" then
        smv_fetch_inventory_descendents(sess, d)
      elseif gid == "TransferRequest" then
        smv_transfer_request(sess, d)
      elseif gid == "AgentCachedTexture" then
	smv_agent_cached_texture(sess, d)
      elseif gid == "EconomyDataRequest" then
      elseif gid == "MoneyBalanceRequest" then
        smv_send_money_balance(sess, d)
      elseif gid == "LogoutRequest" then
        smv_logout_session(sess)
      elseif gid == "ChatFromViewer" then
        smv_chat_from_viewer(sess, d)
      elseif gid == "ParcelPropertiesRequest" then
        smv_parcel_properties_request(sess, d)
      elseif gid == "EstateCovenantRequest" then
        smv_estate_covenant_request(sess, d)
      elseif gid == "ParcelDwellRequest" then
        smv_parcel_dwell_request(sess, d)
      elseif gid == "ParcelAccessListRequest" then
        smv_parcel_access_list_request(sess, d)
      elseif gid == "SetAlwaysRun" then
      elseif gid == "ViewerEffect" then
        smv_viewer_effect(sess, d)
        -- FIXME: alwaysrun
      elseif gid == "AgentSetAppearance" then
        smv_agent_set_appearance(sess, d)
      elseif gid == "AgentIsNowWearing" then
        smv_agent_is_now_wearing(sess, d)
      elseif gid == "UUIDNameRequest" then
        smv_uuid_name_request(sess, d)
      elseif gid == "RequestImage" then
        local bs = fmv.Get_RequestImage_RequestImageBlockSize(d)
        -- print ("Image request blocks: " .. tostring(bs))
      else
        print("Packet received on index " .. tostring(idx) .. " - " .. gid .. "\n")
      end
    else
      print("Could not find session for remote " .. remote_str)
    end
  end
end

smv.coldstart = function()
  smv.start_listener("0.0.0.0", 9000)
  print("Lua SMV startup complete!\n")
end

smv.serialize = function()
  local s = serialize("smv_state", smv_state)
  local s1 = serialize("mv_state", mv_state)
  local f = io.open("luastate.lua", "w+")
  f:write(su.dgetstr(s))
  f:write(su.dgetstr(s1))
  io.close(f)
  su.dunlock(s)
  su.dunlock(s1)
end

function interrupt_save_state()
  print("Interrupted, saving state")
  smv.serialize()
end

print("SMV Lua loaded")
