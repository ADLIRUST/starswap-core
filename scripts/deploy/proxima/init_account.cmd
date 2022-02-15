# bridge合约admin账号
account import -i 0xf4611222ffb7a0d348596132b94ac63f61e78bea4da87d3d9f9009b2abb4ce82
account default 0x2d81a0427d64ff61b11ede9085efa5ad
account unlock 0x2d81a0427d64ff61b11ede9085efa5ad
dev get-coin 0x2d81a0427d64ff61b11ede9085efa5ad

# Swap Fee admin账号
account import -i 0x1f5bfa4af32fe7c0604efba5146e3341153ff8245cc39a1e4000d09727a58f03
account default  0x0a4183ac9335a9f5804014eab01c0abc
account unlock 0x0a4183ac9335a9f5804014eab01c0abc
dev get-coin 0x0a4183ac9335a9f5804014eab01c0abc

# Swap合约admin账号
account import -i 0xb9ac5b4924d01efa8c3e465b5df31416f76907c6deffd8956a5ef508bb87af02
account default 0x2b3d5bd6d0f8a957e6a4abe986056ba7
account unlock 0x2b3d5bd6d0f8a957e6a4abe986056ba7
dev get-coin 0x2b3d5bd6d0f8a957e6a4abe986056ba7

### 部署XUSDT
dev deploy storage/0x2d81a0427d64ff61b11ede9085efa5ad/modules/XUSDT.mv -s 0x2d81a0427d64ff61b11ede9085efa5ad  -b
dev deploy storage/0x2d81a0427d64ff61b11ede9085efa5ad/modules/XUSDTScripts.mv -s 0x2d81a0427d64ff61b11ede9085efa5ad -b

### XUSDT注册/发币
account execute-function  --function 0x2d81a0427d64ff61b11ede9085efa5ad::XUSDTScripts::init -s 0x2d81a0427d64ff61b11ede9085efa5ad -b
account execute-function  --function 0x2d81a0427d64ff61b11ede9085efa5ad::XUSDTScripts::mint --arg 20088888000000000u128 -s 0x2d81a0427d64ff61b11ede9085efa5ad -b

dev package -n swap -o build storage/0x2b3d5bd6d0f8a957e6a4abe986056ba7/
dev deploy -s 0x2b3d5bd6d0f8a957e6a4abe986056ba7  build/swap.blob -b

## 提交带时间设置的升级配置（10s）
account execute-function -s 0x2b3d5bd6d0f8a957e6a4abe986056ba7 --function 0x2b3d5bd6d0f8a957e6a4abe986056ba7::UpgradeScripts::update_module_upgrade_strategy_with_min_time --arg 1u8 --arg 10000u64 -b

### Swap Fee admin账号 accept XUSDT
account execute-function --function 0x1::Account::accept_token -t 0x2d81a0427d64ff61b11ede9085efa5ad::XUSDT::XUSDT -s 0x0a4183ac9335a9f5804014eab01c0abc -b

### 治理币创世初始化
account execute-function  --function 0x2b3d5bd6d0f8a957e6a4abe986056ba7::TokenSwapGovScript::genesis_initialize -s 0x2b3d5bd6d0f8a957e6a4abe986056ba7 -b

### 设置swap operation fee rate
account execute-function  --function 0x2b3d5bd6d0f8a957e6a4abe986056ba7::TokenSwapScripts::set_swap_fee_operation_rate --arg 10u64 --arg 60u64  -s 0x2b3d5bd6d0f8a957e6a4abe986056ba7 -b

### 提取STAR
account execute-function -s 0x2b3d5bd6d0f8a957e6a4abe986056ba7 --function 0x2b3d5bd6d0f8a957e6a4abe986056ba7::TokenSwapGovScript::dispatch -t 0x2b3d5bd6d0f8a957e6a4abe986056ba7::TokenSwapGovPoolType::PoolTypeDaoCrosshain --arg  0x2b3d5bd6d0f8a957e6a4abe986056ba7  --arg 210000000000000u128 -b