import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:ride_on/domain/entities/Sliders_data.dart';

import '../../../data/repositories/profile_repository.dart';

abstract class SlidersState {}

class SlidersInitial extends SlidersState {}

class SlidersLoading extends SlidersState {}

class SlidersSuccess extends SlidersState {
  final SliderResponse sliderResponse;
  SlidersSuccess(this.sliderResponse);
}

class SlidersFailed extends SlidersState {
  final String error;
  SlidersFailed(this.error);
}

class SlidersCubit extends Cubit<SlidersState> {
  final ProfileRepository userProfileRepository;

  SlidersCubit(this.userProfileRepository) : super(SlidersInitial());

  Future<void> getSlidersList(BuildContext context) async {
    emit(SlidersLoading());
    try {
      final response = await userProfileRepository.getSliders(postData: {});

      if (response["status"] == 200) {
        // / Fix: send ONLY response["data"] into SlidersData
        SliderResponse sliderResponse = SliderResponse.fromJson(response);

        emit(SlidersSuccess(sliderResponse));
      } else {
        emit(SlidersFailed(response["error"] ?? "Something went wrong"));
      }
    } catch (e) {
      emit(SlidersFailed(e.toString()));
    }
  }
}
