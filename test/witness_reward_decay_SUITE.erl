%%--------------------------------------------------------------------
%%
%% Test suite group runs through a witness reward scenarios with varying
%% values supplied for the witness decay rate and for the witness decay
%% exclusion count.
%%
%%--------------------------------------------------------------------

-module(witness_reward_decay_SUITE).

-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").
-include("blockchain_ct_utils.hrl").
-include("blockchain_vars.hrl").

-export([
    all/0,
    groups/0,
    init_per_group/2,
    end_per_group/2,
    init_per_testcase/2,
    end_per_testcase/2,
    init_per_suite/1,
    end_per_suite/1
]).

-export([
    no_vars_test/1,
    decay_rate_0_8_test/1
]).

all() ->
    [
        {group, no_vars},
        {group, with_decay}
    ].

no_vars_cases() ->
    [
        no_vars_test
    ].

decay_rate_cases() ->
    [
        decay_rate_0_8_test
    ].

groups() ->
    [
        {no_vars, [], no_vars_cases()},
        {with_decay, [], decay_rate_cases()}
    ].

%%--------------------------------------------------------------------
%% group setup
%%--------------------------------------------------------------------

init_per_group(Group, Config) ->
    ExtraVars =
        case Group of
            no_vars ->
                #{};
            with_decay ->
                #{?witness_reward_decay_exclusion => 4}
        end,

    [{extra_vars, ExtraVars} | Config].

%%--------------------------------------------------------------------
%% group teardown
%%--------------------------------------------------------------------

end_per_group(_, _Config) ->
    ok.

%%--------------------------------------------------------------------
%% suite setup
%%--------------------------------------------------------------------

init_per_suite(Config) ->
    {ok, StorePid} = blockchain_test_reward_store:start(),
    blockchain_test_reward_store:insert(witness_shares, #{}),
    [{store_pid, StorePid} | Config].

%%--------------------------------------------------------------------
%% suite teardown
%%--------------------------------------------------------------------

end_per_suite(_Config) ->
    WitnessShares = blockchain_test_reward_store:fetch(witness_shares),
    ct:print("Witness shares: ~p", [WitnessShares]),
    blockchain_test_reward_store:stop(),
    ok.

%%--------------------------------------------------------------------
%% test case setup
%%--------------------------------------------------------------------

init_per_testcase(TestCase, Config0) ->
    Config = blockchain_ct_utils:init_base_dir_config(?MODULE, TestCase, Config0),
    Balance = 5000,
    BaseDir = ?config(base_dir, Config),
    {ok, Sup, {PrivKey, PubKey}, Opts} = test_utils:init(BaseDir),

    ExtraVars0 = ?config(extra_vars, Config),
    ExtraVars = maps:merge(ExtraVars0, decay_rate(TestCase)),

    {ok, GenesisMembers, _GenesisBlock, ConsensusMembers, Keys} =
        test_utils:init_chain(Balance, {PrivKey, PubKey}, true, ExtraVars),

    Chain = blockchain_worker:blockchain(),
    Swarm = blockchain_swarm:swarm(),
    N = length(ConsensusMembers),

    % Check ledger to make sure everyone has the right balance
    Ledger = blockchain:ledger(Chain),
    Entries = blockchain_ledger_v1:entries(Ledger),
    _ = lists:foreach(
        fun(Entry) ->
            Balance = blockchain_ledger_entry_v1:balance(Entry),
            0 = blockchain_ledger_entry_v1:nonce(Entry)
        end,
        maps:values(Entries)
    ),

    ActiveGateways = blockchain_ledger_v1:active_gateways(Ledger),
    GatewayAddrs = lists:sort(maps:keys(ActiveGateways)),
    AllGws = [a, b, c, d, e, f, g, h, i, j, k],
    %% GatewayNameMap = lists:foldl(
    %%     fun({Letter, A}, Acc) ->
    %%         maps:put(blockchain_utils:addr2name(A), Letter, Acc)
    %%     end,
    %%     #{},
    %%     lists:zip(AllGws, GatewayAddrs)
    %% ),

    %% GatewayLocMap = lists:foldl(
    %%     fun(A, Acc) ->
    %%         {ok, Gw} = blockchain_ledger_gateway_v2:location(Gw),
    %%         maps:put(blockchain_utils:addr2name(A), GwLoc, Acc)
    %%     end,
    %%     #{},
    %%     GatewayAddrs
    %% ),

    GatewayLetterToAddrMap = lists:foldl(
        fun({Letter, A}, Acc) ->
            maps:put(Letter, A, Acc)
        end,
        #{},
        lists:zip(AllGws, GatewayAddrs)
    ),

    Challenger = maps:get(a, GatewayLetterToAddrMap),
    {_, {_, _, ChallengerSigFun}} = lists:keyfind(Challenger, 1, GenesisMembers),

    %% First beaconer (challengee)
    FirstBeaconer = maps:get(c, GatewayLetterToAddrMap),
    %% Receipt for first beaconer
    Rx1 = blockchain_poc_receipt_v1:new(FirstBeaconer, 1000, 10, <<"first_rx">>, p2p),
    %% Witnesses for first beaconer
    ConstructedWitnesses1 = construct_witnesses([b, d], GatewayLetterToAddrMap),

    SecondBeaconer = maps:get(d, GatewayLetterToAddrMap),
    Rx2 = blockchain_poc_receipt_v1:new(SecondBeaconer, 1000, 10, <<"first_rx">>, p2p),
    ConstructedWitnesses2 = construct_witnesses([b, c], GatewayLetterToAddrMap),

    ThirdBeaconer = maps:get(e, GatewayLetterToAddrMap),
    Rx3 = blockchain_poc_receipt_v1:new(ThirdBeaconer, 1000, 10, <<"first_rx">>, p2p),
    ConstructedWitnesses3 = construct_witnesses([b, d], GatewayLetterToAddrMap),

    FourthBeaconer = maps:get(f, GatewayLetterToAddrMap),
    Rx4 = blockchain_poc_receipt_v1:new(FourthBeaconer, 1000, 10, <<"first_rx">>, p2p),
    ConstructedWitnesses4 = construct_witnesses([b, e], GatewayLetterToAddrMap),

    FifthBeaconer = maps:get(g, GatewayLetterToAddrMap),
    Rx5 = blockchain_poc_receipt_v1:new(FifthBeaconer, 1000, 10, <<"first_rx">>, p2p),
    ConstructedWitnesses5 = construct_witnesses([b, f], GatewayLetterToAddrMap),

    ok = create_req_and_poc_blocks(
        Challenger,
        ChallengerSigFun,
        FirstBeaconer,
        Rx1,
        ConstructedWitnesses1,
        ConsensusMembers,
        Chain
    ),
    ok = create_req_and_poc_blocks(
        Challenger,
        ChallengerSigFun,
        SecondBeaconer,
        Rx2,
        ConstructedWitnesses2,
        ConsensusMembers,
        Chain
    ),
    ok = create_req_and_poc_blocks(
        Challenger,
        ChallengerSigFun,
        ThirdBeaconer,
        Rx3,
        ConstructedWitnesses3,
        ConsensusMembers,
        Chain
    ),
    ok = create_req_and_poc_blocks(
        Challenger,
        ChallengerSigFun,
        FourthBeaconer,
        Rx4,
        ConstructedWitnesses4,
        ConsensusMembers,
        Chain
    ),
    ok = create_req_and_poc_blocks(
        Challenger,
        ChallengerSigFun,
        FifthBeaconer,
        Rx5,
        ConstructedWitnesses5,
        ConsensusMembers,
        Chain
    ),

    {ok, Height} = blockchain:height(Chain),
    %% {ok, Rewards} = blockchain_txn_rewards_v2:calculate_rewards(1, Height, Chain),
    {ok, RewardsMd} = blockchain_txn_rewards_v2:calculate_rewards_metadata(1, Height, Chain),
    WitnessRewards = maps:get(poc_witness, RewardsMd),
    ct:print("WitnessRewards : ~p", [WitnessRewards]),

    %% WitnessRewards = lists:filter(
    %%                    fun(Reward) ->
    %%                        blockchain_txn_reward_v1:type(Reward) == poc_witnesses
    %%                    end,
    %%                    Rewards
    %%                   ),

    %% WitnessRewardsMap =
    %%     lists:foldl(
    %%         fun(Reward, Acc) ->
    %%             maps:put(
    %%                 maps:get(
    %%                     blockchain_utils:addr2name(blockchain_txn_reward_v1:gateway(Reward)),
    %%                     GatewayNameMap
    %%                 ),
    %%                 blockchain_txn_reward_v1:amount(Reward),
    %%                 Acc
    %%             )
    %%         end,
    %%         #{},
    %%         WitnessRewards
    %%     ),

    %% ct:print("Witness rewards : ~p", [WitnessRewardsMap]),
    %% GatewayLetterLocMap = lists:foldl(
    %%     fun({letter, A}, Acc) ->
    %%         {ok, Gw} = blockchain_ledger_v1:find_gateway_info(A, Ledger),
    %%         GwLoc = blockchain_ledger_gateway_v2:location(Gw),
    %%         maps:put(Letter, GwLoc, Acc)
    %%     end,
    %%     #{},
    %%     lists:zip(AllGws, GatewayAddrs)
    %% ),
    %% Ledger1 = blockchain_ledger_v1:new_context(Ledger),
    %% EpochVars = #{
    %%     epoch_reward => 1000,
    %%     poc_witnesses_percent => 0.05,
    %%     poc_challengees_percent => 0.0,
    %%     poc_challengers_percent => 0.0,
    %%     dc_remainder => 0,
    %%     poc_version => 10
    %% },

    %% LedgerVars = maps:merge(common_poc_vars(), EpochVars),
    %% ok = blockchain_ledger_v1:vars(LedgerVars, [], Ledger1),

    %% Gateways = [
    %%     {<<"a">>, 631179381270930431},
    %%     {<<"b">>, 631196173757531135},
    %%     {<<"c">>, 631196173214364159},
    %%     {<<"d">>, 631179381325720575},
    %%     {<<"e">>, 631179377081096191},
    %%     {<<"f">>, 631188755337926143},
    %%     {<<"g">>, 631188755339337215}
    %% ],

    %% [add_gateway_to_ledger(Name, Loc, Ledger1) || {Name, Loc} <- Gateways],

    %% ok = blockchain_ledger_v1:commit_context(Ledger1),

    %% WitnessA = blockchain_poc_witness_v1:new(<<"a">>, 1, -80, <<>>),
    %% WitnessB = blockchain_poc_witness_v1:new(<<"b">>, 1, -80, <<>>),
    %% WitnessC = blockchain_poc_witness_v1:new(<<"c">>, 1, -80, <<>>),
    %% WitnessE = blockchain_poc_witness_v1:new(<<"e">>, 1, -80, <<>>),
    %% Elem1 = blockchain_poc_path_element_v1:new(<<"b">>, <<"Receipt not undefined">>, [WitnessA, WitnessC]),
    %% Elem2 = blockchain_poc_path_element_v1:new(<<"c">>, <<"Receipt not undefined">>, [WitnessA, WitnessB]),
    %% Elem3 = blockchain_poc_path_element_v1:new(<<"d">>, <<"Receipt not undefined">>, [WitnessA, WitnessE]),
    %% Elem4 = blockchain_poc_path_element_v1:new(<<"e">>, <<"Receipt not undefined">>, [WitnessA, WitnessB]),
    %% Elem5 = blockchain_poc_path_element_v1:new(<<"f">>, <<"Receipt not undefined">>, [WitnessA, WitnessC]),
    %% Txns = [
    %%         blockchain_txn_poc_receipts_v1:new(<<"d">>, <<"Secret">>, <<"OnionKeyHash">>, [Elem1, Elem1]),
    %%         blockchain_txn_poc_receipts_v1:new(<<"e">>, <<"Secret">>, <<"OnionKeyHash">>, [Elem1, Elem1]),
    %%         blockchain_txn_poc_receipts_v1:new(<<"b">>, <<"Secret">>, <<"OnionKeyHash">>, [Elem2, Elem2]),
    %%         blockchain_txn_poc_receipts_v1:new(<<"d">>, <<"Secret">>, <<"OnionKeyHash">>, [Elem2, Elem2]),
    %%         blockchain_txn_poc_receipts_v1:new(<<"e">>, <<"Secret">>, <<"OnionKeyHash">>, [Elem3, Elem3]),
    %%         blockchain_txn_poc_receipts_v1:new(<<"f">>, <<"Secret">>, <<"OnionKeyHash">>, [Elem3, Elem3]),
    %%         blockchain_txn_poc_receipts_v1:new(<<"c">>, <<"Secret">>, <<"OnionKeyHash">>, [Elem4, Elem4]),
    %%         blockchain_txn_poc_receipts_v1:new(<<"g">>, <<"Secret">>, <<"OnionKeyHash">>, [Elem4, Elem4]),
    %%         blockchain_txn_poc_receipts_v1:new(<<"b">>, <<"Secret">>, <<"OnionKeyHash">>, [Elem5, Elem5]),
    %%         blockchain_txn_poc_receipts_v1:new(<<"g">>, <<"Secret">>, <<"OnionKeyHash">>, [Elem5, Elem5])
    %%        ],

    %% WitnessShares = lists:foldl(fun(T, Acc) -> blockchain_txn_rewards_v2:poc_witness_reward(T, Acc, Chain, Ledger, EpochVars) end,
    %%                             #{}, Txns),
    %% Rewards = blockchain_txn_rewards_v2:normalize_witness_rewards(WitnessShares, EpochVars),
    %% {ok, Height} = blockchain:height(Chain),
    %% {ok, RewardsMd} = blockchain_txn_rewards_v2:calculate_rewards_metadata(1, Height, Chain),
    %% ct:print("Height : ~p, Rewards Metadata: ~p", [Height, RewardsMd]),

    %% ct:print("Witness Shares: ~p; Rewards: ~p", [WitnessShares, Rewards]),

    [
        {balance, Balance},
        {sup, Sup},
        {pubkey, PubKey},
        {privkey, PrivKey},
        {opts, Opts},
        {chain, Chain},
        {ledger, Ledger},
        {swarm, Swarm},
        {n, N},
        {consensus_members, ConsensusMembers},
        {genesis_members, GenesisMembers},
        {base_dir, BaseDir},
        Keys
        | Config
    ].

%%--------------------------------------------------------------------
%% test case teardown
%%--------------------------------------------------------------------

end_per_testcase(_TestCase, _Config) ->
    ok.

%%--------------------------------------------------------------------
%% test cases
%%--------------------------------------------------------------------

no_vars_test(_Config) ->
    stash_witness_shares(no_vars, 1),
    ok.

decay_rate_0_8_test(_Config) ->
    stash_witness_shares(zero_point_eight, 2),
    ok.

stash_witness_shares(Key, Value) ->
    WitnessShares = blockchain_test_reward_store:fetch(witness_shares),
    WitnessShares0 = maps:merge(WitnessShares, #{Key => Value}),
    blockchain_test_reward_store:insert(witness_shares, WitnessShares0),
    ok.

%% add_gateway_to_ledger(Name, Location, Ledger) ->
%%     ok = blockchain_ledger_v1:add_gateway(<<"o">>, Name, Ledger),
%%     ok = blockchain_ledger_v1:add_gateway_location(Name, Location, 1, Ledger),
%%     ok.

decay_rate(no_vars_test) ->
    #{};
decay_rate(Case) ->
    Rate = maps:get(Case, #{
        decay_rate_0_6_test => 0.6,
        decay_rate_0_7_test => 0.7,
        decay_rate_0_8_test => 0.8,
        decay_rate_0_9_test => 0.9,
        decay_rate_1_0_test => 1.0
    }),
    #{?witness_reward_decay_rate => Rate}.

%% common_poc_vars() ->
%%     #{
%%         ?poc_v4_exclusion_cells => 10,
%%         ?poc_v4_parent_res => 11,
%%         ?poc_v4_prob_bad_rssi => 0.01,
%%         ?poc_v4_prob_count_wt => 0.3,
%%         ?poc_v4_prob_good_rssi => 1.0,
%%         ?poc_v4_prob_no_rssi => 0.5,
%%         ?poc_v4_prob_rssi_wt => 0.3,
%%         ?poc_v4_prob_time_wt => 0.3,
%%         ?poc_v4_randomness_wt => 0.1,
%%         ?poc_v4_target_challenge_age => 300,
%%         ?poc_v4_target_exclusion_cells => 6000,
%%         ?poc_v4_target_prob_edge_wt => 0.2,
%%         ?poc_v4_target_prob_score_wt => 0.8,
%%         ?poc_v4_target_score_curve => 5,
%%         ?poc_v5_target_prob_randomness_wt => 0.0
%%     }.

construct_witnesses(WitnessList, GatewayLetterToAddrMap) ->
    lists:foldl(
        fun(W, Acc) ->
            WitnessGw = maps:get(W, GatewayLetterToAddrMap),
            Witness = blockchain_poc_witness_v1:new(
                WitnessGw,
                1001,
                10,
                crypto:strong_rand_bytes(32),
                9.800000190734863,
                915.2000122070313,
                10,
                "data_rate"
            ),
            [Witness | Acc]
        end,
        [],
        WitnessList
    ).

create_req_and_poc_blocks(
    Challenger, ChallengerSigFun, Beaconer, Rx, Witnesses, ConsensusMembers, Chain
) ->
    Secret = crypto:strong_rand_bytes(32),
    OnionKeyHash = crypto:strong_rand_bytes(32),
    BlockHash = crypto:strong_rand_bytes(32),

    ReqTxn = blockchain_txn_poc_request_v1:new(Challenger, Secret, OnionKeyHash, BlockHash, 10),
    SignedReqTxn = blockchain_txn_poc_request_v1:sign(ReqTxn, ChallengerSigFun),

    Poc = blockchain_poc_path_element_v1:new(Beaconer, Rx, Witnesses),
    PocTxn = blockchain_txn_poc_receipts_v1:new(Challenger, Secret, OnionKeyHash, BlockHash, [Poc]),
    SignedPocTxn = blockchain_txn_poc_receipts_v1:sign(PocTxn, ChallengerSigFun),

    meck:expect(
        blockchain_txn_poc_receipts_v1,
        good_quality_witnesses,
        fun
            (E, _) when E == Poc ->
                Witnesses;
            (_, _) ->
                []
        end
    ),

    meck:expect(
        blockchain_txn_poc_receipts_v1,
        valid_witnesses,
        fun
            (E, _, _) when E == Poc ->
                Witnesses;
            (_, _, _) ->
                []
        end
    ),

    meck:expect(blockchain_txn_poc_request_v1, is_valid, fun(_, _) -> ok end),
    meck:expect(blockchain_txn_poc_receipts_v1, is_valid, fun(_, _) -> ok end),
    meck:expect(blockchain_txn_poc_receipts_v1, absorb, fun(_, _) -> ok end),
    meck:expect(blockchain_txn_poc_receipts_v1, get_channels, fun(_, _) ->
        {ok, lists:seq(1, 11)}
    end),

    {ok, ReqBlock} = test_utils:create_block(ConsensusMembers, [SignedReqTxn], #{}, false),
    _ = blockchain_gossip_handler:add_block(ReqBlock, Chain, self(), blockchain_swarm:swarm()),

    {ok, PocBlock} = test_utils:create_block(ConsensusMembers, [SignedPocTxn], #{}, false),
    _ = blockchain_gossip_handler:add_block(PocBlock, Chain, self(), blockchain_swarm:swarm()),

    ok.
